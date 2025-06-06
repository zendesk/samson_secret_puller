# frozen_string_literal: true

source 'https://rubygems.org'

ruby "~> #{File.read(Bundler.root.join('.ruby-version'))[/\d+\.\d/]}"

gem 'vault', ">= 0.5.0"

unless ENV["SKIP_DEV_GEMS"] # `bundle set without` still leaves the gems in Gemfile.lock which wiz picks up
  group :test do
    gem 'maxitest'
    gem 'mocha'
    gem 'webmock'
    gem 'single_cov'
    gem 'rubocop'
    gem 'rack'
    gem 'bump'
    gem 'rake'
    gem 'hashdiff', '~> 0.3.9' # https://github.com/liufengyun/hashdiff/issues/66
    gem 'stub_server'
    gem 'forking_test_runner'
  end
end
