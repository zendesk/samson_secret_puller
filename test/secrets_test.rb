require 'bundler/setup'

require 'single_cov'
SingleCov.setup :minitest
SingleCov.covered! uncovered: 5

require 'maxitest/autorun'
require 'webmock/minitest'
require 'tmpdir'

require_relative "../lib/secrets.rb"

describe SecretsClient do
  let(:client) { SecretsClient.new('https://foo.bar:8200', 'vaultpem', false, 'annotations', @dir) }

  before do
    stub_request(:post, "https://foo.bar:8200/v1/auth/cert/login").
      to_return(body: {auth: {client_token: 'sometoken'}}.to_json)
  end

  around do |test|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        @dir = dir + "/"
        File.write('vaultpem', File.read(File.expand_path("../fixtures/test.pem", __FILE__)))
        File.write('annotations', "secret/this/is/my/SECRET")
        test.call
      end
    end
  end

  describe "#initialize" do
    it "works" do
      client
    end

    it "fails to initialize with missing pem" do
      File.delete('vaultpem')
      assert_raises(RuntimeError) { client }
    end

    it "fails to initialize with missing annotations" do
      File.delete('annotations')
      assert_raises(RuntimeError) { client }
    end
  end

  describe "#process" do
    let(:reply) { {data: {vault: 'foo'}}.to_json }

    before do
      stub_request(:get, 'https://foo.bar:8200/v1/secret%2Fsecret%2Fthis%2Fis%2Fmy%252FSECRET').
        to_return(body: reply, headers: {'Content-Type': 'application/json'})
    end

    it 'works' do
      client.process
      File.read('/tmp/SECRET').must_equal("foo")
    end

    it 'ignores newline in key name' do
      File.write('annotations', File.read('annotations') + "\n")
      client.process
      File.read('/tmp/SECRET').must_equal("foo")
    end

    it "raises when response is invalid" do
      reply.replace({foo: {bar: 1}}.to_json)
      assert_raises(RuntimeError) { client.process }
    end
  end
end
