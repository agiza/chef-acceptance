require "chef-acceptance/output_formatter"
require "chef-acceptance/chef_runner"
require "chef-acceptance/test_suite"
require "chef-acceptance/executable_helper"

module ChefAcceptance
  class AcceptanceFatalError < StandardError; end

  # Responsible for running one or more suites and
  # displaying statistics about the runs to the user.
  class Application
    attr_reader :force_destroy
    attr_reader :output_formatter
    attr_reader :errors

    def initialize(options = {})
      @force_destroy = options.fetch("force_destroy", false)
      @output_formatter = OutputFormatter.new
      @errors = {}
    end

    def run(suite_regex, command)
      begin
        suites = parse_suites(suite_regex)

        puts "Running test suites:"
        puts suites.join("\n")
        puts ""

        # Start the overall run timer
        run_start_time = Time.now

        suites.each do |suite|
          suite_start_time = Time.now

          begin
            run_suite(suite, command)
          rescue RuntimeError => e
            # We catch the errors here and do not raise again in
            # order to make a clean exit. Since the errors are already
            # in stdout, we do not print them again.
            errors[suite] = e
          ensure
            suite_duration = Time.now - suite_start_time
            # Capture overall suite run duration
            output_formatter.add_row(suite: suite, command: "Total", duration: suite_duration, error: errors[suite])
          end
        end

        total_duration = Time.now - run_start_time
        # Special footer row that gives overall status for run
        output_formatter.add_row(suite: "Run", command: "Total", duration: total_duration, error: run_error?)
        print_summary
      rescue AcceptanceFatalError => e
        puts ""
        puts e
        exit(1)
      end

      # Make sure that exit code reflects the error if we have any
      exit(1) if run_error?
    end

    def run_error?
      !errors.empty?
    end

    # Parse the regex pattern and return an array of matching test suite names
    def parse_suites(regex)
      # Find all directories in cwd
      suites = Dir.glob("*").select { |f| File.directory? f }
      raise AcceptanceFatalError, "No test suites to run in #{Dir.pwd}" if suites.empty?

      # Find all test suites that match the regex pattern
      matched_suites = suites.select { |s| /#{regex}/ =~ s }
      raise AcceptanceFatalError, "No matching test suites found using regex '#{regex}'" if matched_suites.empty?

      matched_suites
    end

    def run_suite(suite, command)
      test_suite = TestSuite.new(suite)

      unless ExecutableHelper.executable_installed? "chef-client"
        raise AcceptanceFatalError, "Could not find chef-client in #{ENV['PATH']}"
      end

      if command == "test"
        %w{provision verify destroy}.each do |recipe|
          begin
            run_command(test_suite, recipe)
          rescue RuntimeError => e
            puts "Encountered an error running the recipe #{recipe}: #{e.message}\n#{e.backtrace.join("\n")}"
            if force_destroy && recipe != "destroy"
              puts "--force-destroy specified so attempting to run the destroy recipe"
              run_command(test_suite, "force-destroy")
            end
            raise
          end
        end
      else
        run_command(test_suite, command)
      end
    end

    def run_command(test_suite, command)
      recipe = command == "force-destroy" ? "destroy" : command
      runner = ChefRunner.new(test_suite, recipe)
      error = false
      begin
        runner.run!
      rescue
        error = true
        raise
      ensure
        output_formatter.add_row(suite: test_suite.name, command: command, duration: runner.duration, error: error)
      end
    end

    def print_summary
      puts ""
      puts "chef-acceptance run #{run_error? ? "failed" : "succeeded"}"
      puts output_formatter.generate_output
      puts ""
    end

  end
end