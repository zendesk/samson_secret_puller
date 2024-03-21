# frozen_string_literal: true

require 'bundler/setup'

require 'single_cov'
SingleCov.setup :minitest

require 'maxitest/global_must'
require 'maxitest/autorun'
require 'webmock/minitest'
require 'tmpdir'
require 'mocha/minitest'
require 'stub_server'

def root
  Bundler.root.to_s
end

Thread.abort_on_exception = true

Minitest::Test.class_eval do
  def with_env(env)
    old = env.keys.map { |k| [k, ENV[k.to_s]] }
    env.each { |k, v| ENV[k.to_s] = v }
    yield
  ensure
    old.each { |k, v| ENV[k.to_s] = v }
  end

  def sh(command, fail: false)
    result = `#{command} 2>&1`
    raise "FAILED #{result}" if $?.success? == fail
    result
  end
end
