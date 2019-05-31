# frozen_string_literal: true

require_relative 'test_helper'

SingleCov.not_covered!

describe ",osc" do
  it "documents all env vars" do
    env = /[A-Z_\d]{5,}/
    supported = File.read("bin/secrets").scan(env) - ["STDOUT", "KUBERNETES_PORT_443_TCP_ADDR", "TESTING"]
    documented = File.read("README.md").scan(env) - ["README"]
    (documented - supported).must_equal []
    (supported - documented).must_equal []
  end
end
