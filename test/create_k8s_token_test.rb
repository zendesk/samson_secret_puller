# frozen_string_literal: true

require_relative 'test_helper'
require 'rack'
require 'json'
require 'open-uri'

SingleCov.not_covered!

describe 'CRON' do
  let(:vault_replies) do
    {
      '/auth/token/create' =>
        {
          "auth": {
            "client_token": "ABCD",
            "policies": ["web", "stage"],
            "metadata": {"user": "armon"},
            "lease_duration": 3600,
            "renewable": true,
          }
        },
      '/auth' => {}
    }
  end
  let(:kuber_replies) do
    {
      '/api/v1/namespaces/default/secrets/vaultauth' => {},
    }
  end

  around do |test|
    WebMock.disable!
    StubServer.open(8200, vault_replies) do |vault|
      StubServer.open(8443, kuber_replies) do |kube|
        vault.wait
        kube.wait
        with_env(
          CRON_TEST: 'true',
          VAULT_PORT: "8200",
          BUNDLER_ROOT: Bundler.root.to_s,
          &test
        )
      end
    end
  end

  def create_token(args, **kwargs)
    sh("#{root}/bin/create_k8s_token.sh #{args}", **kwargs)
  end

  it "can run the cron job" do
    create_token("-v http://localhost:8200 -t faketoken -k #{root}/test/fixutes/kube_config")
  end

  it "fails w/o the server listening" do
    with_env(VAULT_PORT: "8201") do
      create_token("-v http://localhost:9090 -t faketoken -k /etc/password", fail: true).
        must_include("could not get token for secret puller")
    end
  end

  it "fails with missing token" do
    create_token("-v http://foo.bar:1234", fail: true).must_include("VAULT_TOKEN missing")
  end

  it "fails with missing vault address" do
    create_token("-t notatoken", fail: true).must_include("VAULT_ADDR missing")
  end
end
