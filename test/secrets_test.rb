require_relative 'test_helper'

SingleCov.covered!

require_relative "../lib/secrets.rb"

describe SecretsClient do
  def process
    old = $stdout
    $stdout = StringIO.new
    client.write_secrets
  ensure
    $stdout = old
  end

  let(:client) do
    SecretsClient.new(
      vault_address: 'https://foo.bar:8200',
      pemfile_path: 'vaultpem',
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
    ENV["KUBERNETES_PORT_443_TCP_ADDR"] = 'foo.bar'
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

    describe "api failures" do
      before do
        stub_request(:get, "https://foo.bar/api/v1/namespaces/default/pods").
          to_return(status: 500)
      end

      it "raises when api calls fail" do
        assert_raises(RuntimeError) { process }
      end
    end
  end
end
