require 'bundler/setup'
require 'yaml'

travis = YAML.load_file(Bundler.root.join('.travis.yml')).
  fetch('env').
  map { |v| v.delete('TASK=') }

task default: travis

desc "Test"
task :test do
  sh "mtest test/cli_test.rb"
  sh "mtest test/secrets_test.rb"
  sh "mtest test/create_k8s_token_test.rb"
  sh "mtest gem/test/" # need to be separate runs so we do not pollute anything
end

desc "Rubocop"
task :rubocop do
  sh "rubocop --display-cop-names"
end
