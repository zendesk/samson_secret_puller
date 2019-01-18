require_relative 'test_helper'
require 'open-uri'
require 'timeout'
require 'rack'

describe "CLI" do
  let(:port) { 8211 }

  around do |test|
    WebMock.disable!
    test.call
    WebMock.enable!
  end

  around { |test| Dir.mktmpdir { |dir| Dir.chdir(dir) { test.call } } }

  it "dumps secrets" do
    File.write('pem', File.read("#{Bundler.root}/test/fixtures/self_signed_testing.pem"))
    File.write('ca.crt', File.read("#{Bundler.root}/test/fixtures/self_signed_testing.pem"))
    File.write('token', File.read("#{Bundler.root}/test/fixtures/fake_token"))
    File.write('namespace', File.read("#{Bundler.root}/test/fixtures/namespace"))
    File.write('input', 'secret/BAR=foo/bar/baz/bam')

    # mix of vault and kubernetes for simplicity
    replies = {
      '/v1/auth/cert/login' => {auth: {client_token: 'sometoken'}},
      '/v1/secret/apps/foo/bar/baz/bam' => {data: {vault: 'foo'}},
      '/api/v1/namespaces/default/pods' => {items: [{status: {hostIP: "10.10.10.10"}}]}
    }

    FakeServer.open(port, replies) do |server|
      server.wait
      with_env(
        TESTING: 'true',
        VAULT_ADDR: "http://localhost:#{port}",
        VAULT_AUTH_FILE: 'pem',
        VAULT_TLS_VERIFY: 'false',
        SIDECAR_SECRET_PATH: Dir.pwd,
        SERVICEACCOUNT_DIR: Dir.pwd,
        SECRET_ANNOTATIONS: 'input',
        KUBERNETES_PORT_443_TCP_ADDR: "localhost:#{port}"
      ) do
        sh "#{Bundler.root}/bin/secrets"
        File.read('BAR').must_equal('foo') # secret was written out
      end
    end
  end
end
