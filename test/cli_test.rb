require_relative 'test_helper'
require 'open-uri'
require 'timeout'
require 'rack'

describe "CLI" do
  around do |test|
    WebMock.disable!
    test.call
    WebMock.enable!
  end

  around { |test| Dir.mktmpdir { |dir| Dir.chdir(dir) { test.call } } }

  it "dumps secrets" do
    File.write('pem', File.read("#{Bundler.root}/test/fixtures/test.pem"))
    File.write('ca.crt', File.read("#{Bundler.root}/test/fixtures/test.pem"))
    File.write('token', File.read("#{Bundler.root}/test/fixtures/token"))
    File.write('namespace', File.read("#{Bundler.root}/test/fixtures/namespace"))
    File.write('input', 'secret/BAR=foo/bar/baz/bam')

    replies = {
      '/v1/auth/cert/login' => {auth: {client_token: 'sometoken'}},
      '/v1/secret%2Fapps%2Ffoo%2Fbar%2Fbaz%2Fbam' => {data: {vault: 'foo'}},
      '/api/v1/namespaces/default/pods' => {items: [{status: {hostIP: "10.10.10.10"}}]}
    }

    FakeServer.open(8211, replies) do |server|
      server.wait
      with_env(
        TESTING: 'true',
        VAULT_ADDR: 'http://localhost:8211',
        VAULT_AUTH_FILE: 'pem',
        VAULT_TLS_VERIFY: 'false',
        SIDECAR_SECRET_PATH: Dir.pwd,
        SERVICEACCOUNT_DIR: Dir.pwd,
        SECRET_ANNOTATIONS: 'input',
        KUBERNETES_PORT_443_TCP_ADDR: 'localhost:8211'
      ) do
        sh "#{Bundler.root}/bin/secrets"
        File.read('BAR').must_equal('foo')
      end
    end
  end
end
