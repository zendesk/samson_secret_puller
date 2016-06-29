require_relative 'test_helper'

SingleCov.covered!

require_relative "../lib/secrets.rb"

describe SecretsClient do
  ENV["KUBERNETES_PORT_443_TCP_ADDR"] = 'foo.bar'
  def process
    old = $stdout
    $stdout = StringIO.new
    client.write_secrets
  ensure
    $stdout = old
  end

  let(:token_client) do
    SecretsClient.new(
      vault_address: 'https://foo.bar:8200',
      authfile_path: 'token',
      ssl_verify: false,
      annotations: 'annotations',
      serviceaccount_dir: Dir.pwd,
      output_path: Dir.pwd,
      api_url: 'https://foo.bar'
    )
  end
  let(:client) do
    SecretsClient.new(
      vault_address: 'https://foo.bar:8200',
      authfile_path: 'vaultpem',
      ssl_verify: false,
      annotations: 'annotations',
      serviceaccount_dir: Dir.pwd,
      output_path: Dir.pwd,
      api_url: 'https://foo.bar'
    )
  end
  let(:auth_reply) { {auth: {client_token: 'sometoken'}}.to_json }
  let(:status_api_body) { {items: [{status: {hostIP: "10.10.10.10"}}]}.to_json }

  before do
    stub_request(:post, "https://foo.bar:8200/v1/auth/cert/login").
      to_return(body: auth_reply)
    stub_request(:get, "https://foo.bar/api/v1/namespaces/default/pods").
      to_return(body: status_api_body)
  end

  around do |test|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("vaultpem", File.read(Bundler.root.join("test/fixtures/test.pem")))
        File.write("ca.crt", File.read(Bundler.root.join("test/fixtures/test.pem")))
        File.write("namespace", File.read(Bundler.root.join("test/fixtures/namespace")))
        File.write("token", File.read(Bundler.root.join("test/fixtures/token")))
        File.write('annotations', "secret/SECRET=this/is/very/hidden")
        test.call
      end
    end
  end

  describe "#initialize" do
    it "works with a pem" do
      client
    end

    it "works with a token" do
      token_client
    end

    it "fails to initialize with missing pem" do
      File.delete('vaultpem')
      assert_raises(RuntimeError) { client }
    end

    it "fails to initialize with missing token" do
      File.delete('token')
      assert_raises(RuntimeError) { token_client }
    end

    it "fails to initialize with missing annotations" do
      File.delete('annotations')
      assert_raises(RuntimeError) { client }
    end
  end

  describe "#process" do
    let(:reply) { {data: {vault: 'foo'}}.to_json }
    let(:url) { 'https://foo.bar:8200/v1/secret%2Fapps%2Fthis%2Fis%2Fvery%2Fhidden' }

    before do
      stub_request(:get, url).to_return(body: reply, headers: {'Content-Type': 'application/json'})
    end

    it 'works' do
      process
      File.read("SECRET").must_equal("foo")
    end

    it 'ignores newline in key name' do
      File.write('annotations', File.read('annotations') + "\n")
      process
      File.read("SECRET").must_equal("foo")
    end

    it 'ignores non-secrets' do
      File.write('annotations', File.read('annotations') + "\n" + "other-annotation=this/is/not/hidden")
      process
      assert File.exist?("SECRET")
    end

    it 'raises when no secrets were used' do
      File.write('annotations', "other-annotation=this/is/not/hidden")
      assert_raises(RuntimeError) { process }
      refute File.exist?("SECRET")
    end

    it "raises when response is invalid" do
      reply.replace({foo: {bar: 1}}.to_json)
      assert_raises(RuntimeError) { process }
    end

    it "raises when response is not 200" do
      stub_request(:post, "https://foo.bar:8200/v1/auth/cert/login").
        to_return(status: 500)
      e = assert_raises(RuntimeError) { process }
      e.message.must_include("Could not POST https://foo.bar:8200/v1/auth/cert/login: 500 /")
    end

    describe 'HOST_IP' do
      it 'creates a HOST_IP secret' do
        process
        File.read("HOST_IP").must_equal("10.10.10.10")
      end

      it "raises when host ip api call fails" do
        stub_request(:get, "https://foo.bar/api/v1/namespaces/default/pods").
          to_return(status: 500)
        e = assert_raises(RuntimeError) { process }
        e.message.must_include("Could not GET https://foo.bar/api/v1/namespaces/default/pod")
      end
    end
  end
end
