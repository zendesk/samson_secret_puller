require_relative 'test_helper'
require 'open-uri'
require 'timeout'
require 'rack'

describe "CLI" do
  let(:port) { 8211 }
  let(:replies) do
    # mix of vault and kubernetes for simplicity
    {
      '/v1/auth/cert/login' => {auth: {client_token: 'sometoken', policies: ['foo']}},
      '/v1/auth/token/lookup-self' => {data: {id: 'sometoken', policies: ['foo']}},
      '/v1/secret/apps/foo/bar/baz/bam' => {data: {vault: 'foo'}},
      '/api/v1/namespaces/default/pods' => {items: [{status: {hostIP: "10.10.10.10"}}]}
    }
  end

  around { |test| Dir.mktmpdir { |dir| Dir.chdir(dir) { test.call } } }

  around do |test|
    WebMock.disable!
    FakeServer.open(port, replies) do |server|
      server.wait
      test.call
    end
    WebMock.enable!
  end

  before do
    File.write('namespace', File.read("#{Bundler.root}/test/fixtures/namespace"))
    File.write('input', 'secret/BAR=foo/bar/baz/bam')
    File.write('token', File.read("#{Bundler.root}/test/fixtures/fake_token"))
  end

  context "using certificates" do
    before do
      File.write('pem', File.read("#{Bundler.root}/test/fixtures/self_signed_testing.pem"))
      File.write('ca.crt', File.read("#{Bundler.root}/test/fixtures/self_signed_testing.pem"))
    end

    it "dumps secrets" do
      with_env(
        TESTING: 'true',
        VAULT_ADDR: "http://localhost:#{port}",
        VAULT_AUTH_FILE: 'pem',
        VAULT_AUTH_TYPE: 'cert',
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

  context "using token" do
    it "dumps secrets" do
      with_env(
        TESTING: 'true',
        VAULT_ADDR: "http://localhost:#{port}",
        VAULT_AUTH_FILE: 'token',
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
