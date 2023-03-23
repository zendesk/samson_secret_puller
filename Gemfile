# frozen_string_literal: true

source 'https://rubygems.org'

ruby "~> #{File.read(Bundler.root.join('.ruby-version'))[/\d+\.\d/]}"

gem 'vault', ">= 0.5.0"

group :test do
  gem 'maxitest', '~> 3.1'
  gem 'mocha', '~> 1.8'
  gem 'webmock', '~> 3.5'
  gem 'single_cov', '~> 1.3'
  gem 'rubocop', '~> 0.71'
  gem 'rack', '~> 2.0'
  gem 'bump', '~> 0.8'
  gem 'rake', '~> 12.3'
  gem 'hashdiff', '~> 0.3.9' # https://github.com/liufengyun/hashdiff/issues/66
  gem 'stub_server', '~> 0.4'
  gem 'forking_test_runner', '~> 1.4'
end
