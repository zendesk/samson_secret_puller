require 'bundler/setup'
require 'yaml'

travis = YAML.load_file(Bundler.root.join('.travis.yml')).
  fetch('env').
  map { |v| v.delete('TASK=') }

task default: travis

desc "Test"
task :test do
  sh "mtest test/"
end

desc "Rubocop"
task :rubocop do
  sh "rubocop --display-cop-names"
end
