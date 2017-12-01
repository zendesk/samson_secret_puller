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
  sh "cd elixir && mix test"
end

desc "Rubocop"
task :rubocop do
  sh "rubocop"
end

desc "Build a new version"
task :build do
  sh "docker build -t zendesk/samson_secret_puller ."
end

desc "Run tests in docker"
task test_in_docker: :build do
  sh "docker run -it --rm zendesk/samson_secret_puller rake"
end

desc "Release a new version"
task release: :build do
  sh "docker tag -f zendesk/samson_secret_puller zendesk/samson_secret_puller:latest"
  sh "docker push zendesk/samson_secret_puller:latest"
end
