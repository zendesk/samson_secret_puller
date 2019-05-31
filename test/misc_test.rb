# frozen_string_literal: true

require_relative 'test_helper'

SingleCov.not_covered!

describe "misc" do
  it "documents all env vars" do
    env = /[A-Z_\d]{5,}/
    supported = File.read("bin/secrets").scan(env) - ["STDOUT", "KUBERNETES_PORT_443_TCP_ADDR", "TESTING", "SIGTERM"]
    documented = File.read("README.md").scan(env) - ["README"]
    (documented - supported).must_equal []
    (supported - documented).must_equal []
  end

  it "uses the same version in all dockerfiles" do
    File.read("Dockerfile")[/FROM .*/].must_equal File.read("Dockerfile.dev")[/FROM .*/]
  end
end
