# frozen_string_literal: true

require_relative 'test_helper'

SingleCov.not_covered!

describe "misc" do
  it "documents all env vars" do
    env = /[A-Z_\d]{6,}/
    supported = File.read("bin/secrets").scan(env) - ["STDOUT", "KUBERNETES_PORT_443_TCP_ADDR", "TESTING", "SIGTERM"]
    documented = File.read("README.md").scan(env) - ["README"]
    assert_equal [], (documented - supported)
    assert_equal [], (supported - documented)
  end

  it "uses the same version in all dockerfiles" do
    assert_equal File.read("Dockerfile.dev")[/FROM .*/], File.read("Dockerfile")[/FROM .*/]
  end
end
