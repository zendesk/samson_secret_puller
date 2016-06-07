require 'bundler/setup'

task default: [:test, :rubocop]

desc "Test"
task :test do
  sh "mtest test/"
end

desc "Rubocop"
task :rubocop do
  sh "rubocop --display-cop-names"
end
