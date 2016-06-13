require 'bundler/setup'

require 'single_cov'
SingleCov.setup :minitest

require 'maxitest/autorun'
require 'webmock/minitest'
require 'tmpdir'

Thread.abort_on_exception = true

def with_env(env)
  old = env.map do |k, v|
    k = k.to_s
    o = ENV[k]
    ENV[k] = v
    [k, o]
  end
  yield
ensure
  old.each { |k, v| ENV[k] = v }
end
