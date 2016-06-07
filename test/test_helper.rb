require 'bundler/setup'

require 'single_cov'
SingleCov.setup :minitest

require 'maxitest/autorun'
require 'webmock/minitest'
require 'tmpdir'

Thread.abort_on_exception = true
