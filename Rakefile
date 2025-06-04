# frozen_string_literal: true

require 'bundler/setup'
require 'bundler/gem_helper'
Bundler::GemHelper.new('gem').install # overriding base folder so that `rake release` can find the gemspec

require 'yaml'

task default: ["test", "rubocop"] # keep in sync with .github/workflows/actions.yml

desc "Test"
task :test do
  sh "forking-test-runner test --merge-coverage --quiet"
  sh "mtest gem/test/" # need to be separate runs so we do not pollute anything
  sh "cd elixir && mix test"
end

desc "Rubocop"
task :rubocop do
  sh "rubocop"
end

desc "Build a new version"
task :build do
  revision = `git rev-parse HEAD`.strip
  raise unless $?.success?
  sh "docker", "build", "--label", "revision=#{revision}", "-t", "zendesk/samson_secret_puller", "."
end

desc "Build a new dev version"
task :build_dev do
  sh "docker build -t zendesk/samson_secret_puller-dev -f Dockerfile.dev ."
end

desc "Run tests in docker"
task test_in_docker: :build_dev do
  sh "docker run -it --rm zendesk/samson_secret_puller-dev rake"
end
