execute 'kitchen destroy' do
  cwd File.join(File.dirname(__FILE__), "../../../../../../../..")
end

log 'the destroy recipe'
