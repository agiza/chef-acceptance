execute 'kitchen verify' do
  cwd File.join(File.dirname(__FILE__), "../../../../../../../..")
end

log 'the verify recipe'
