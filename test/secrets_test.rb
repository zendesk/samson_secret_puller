require_relative 'test_helper'

SingleCov.covered!

require_relative "../lib/secrets.rb"
require "logger"

ENV["KUBERNETES_PORT_443_TCP_ADDR"] = 'foo.bar'
ENV["testing"] = "true"

describe SecretsClient do
  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = old
  end

  def process_secrets
    capture_stdout { client.write_secrets }
  end

  def process_pki_certs
    capture_stdout { client.write_pki_certs }
  end

  def response_body(body)
    {body: body, headers: {'Content-Type': 'application/json'}}
  end

  let(:client_options) do
    {
      vault_address: 'https://foo.bar:8200',
      vault_authfile_path: 'token',
      vault_prefix: 'apps',
      vault_mount: 'secret',
      ssl_verify: false,
      annotations: 'annotations',
      serviceaccount_dir: Dir.pwd,
      output_path: Dir.pwd,
      api_url: 'https://foo.bar',
      vault_v2: false,
      logger: logger
    }
  end
  let(:logger) { Logger.new(STDOUT) }
  let(:token_client) { SecretsClient.new(client_options) }
  let(:client) do
    client_options[:vault_authfile_path] = "vaultpem"
    SecretsClient.new(client_options)
  end
  let(:auth_reply) { {auth: {client_token: 'sometoken'}}.to_json }
  let(:status_api_body) { {items: [{status: {hostIP: "10.10.10.10"}}]}.to_json }

  before do
    logger.stubs(:info)
    stub_request(:post, "https://foo.bar:8200/v1/auth/cert/login").
      to_return(body: auth_reply)
    stub_request(:get, "https://foo.bar/api/v1/namespaces/default/pods").
      to_return(body: status_api_body)
  end

  around do |test|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("vaultpem", File.read(Bundler.root.join("test/fixtures/self_signed_testing.pem")))
        File.write("ca.crt", File.read(Bundler.root.join("test/fixtures/self_signed_testing.pem")))
        File.write("namespace", File.read(Bundler.root.join("test/fixtures/namespace")))
        File.write("token", File.read(Bundler.root.join("test/fixtures/fake_token")))
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
        TEXT
        # pki/example.com="pki/issue/example-com?common_name=example.com"
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

  describe "#process_secrets" do
    let(:reply) { {data: {vault: 'foo'}}.to_json }
    let(:url) { +'https://foo.bar:8200/v1/secret/apps/this/is/very/hidden' }

    before do
      stub_request(:get, url).to_return(response_body(reply))
    end

    it 'works' do
      process_secrets
      File.read("SECRET").must_equal("foo")
    end

    it 'logs' do
      logger.unstub(:info)
      logger.expects(:info).with(message: "secrets found", keys: [["SECRET", "this/is/very/hidden"]])
      logger.expects(:info).with(message: "PKI found", keys: []) # ["example.com", "pki/issue/example-com?common_name=example.com"]])
      logger.expects(:info).with(message: "secrets written")
      process_secrets
    end

    it 'ignores newline in key name' do
      File.write('annotations', File.read('annotations') + "\n")
      process_secrets
      File.read("SECRET").must_equal("foo")
    end

    it 'ignores = in path' do
      url.sub!('hidden', 'hi=dden') || raise
      request = stub_request(:get, url).to_return(response_body({data: {vault: 'foo'}}.to_json))
      File.write('annotations', File.read('annotations').sub!("hidden", "hi=dden"))

      process_secrets

      File.read("SECRET").must_equal("foo")
      assert_requested request
    end

    it 'ignores non-secrets' do
      File.write('annotations', File.read('annotations') + "\n" + "OTHER=\"this/is/not/hidden\"")
      process_secrets
      assert File.exist?("SECRET")
      refute File.exist?("OTHER")
    end

    it 'can read v2' do
      client_options[:vault_v2] = true
      url.sub!('/apps', '/data/apps') || raise
      request = stub_request(:get, url).to_return(response_body({data: {data: {vault: 'foo'}}}.to_json))

      process_secrets

      File.read("SECRET").must_equal("foo")
      assert_requested request
    end

    it 'raises when no secrets were used' do
      File.write('annotations', "other-annotation=\"this/is/not/hidden\"")
      assert_raises(RuntimeError) { process_secrets }
      refute File.exist?("SECRET")
    end

    it "raises when response is invalid" do
      reply.replace({foo: {bar: 1}}.to_json)
      assert_raises(RuntimeError) { process_secrets }
    end

    it "raises when response is not 200" do
      stub_request(:post, "https://foo.bar:8200/v1/auth/cert/login").
        to_return(status: 500)
      e = assert_raises(RuntimeError) { process_secrets }
      e.message.must_include("Could not POST https://foo.bar:8200/v1/auth/cert/login: 500 /")
    end

    it 'raises useful debugging info when a timeout is encountered' do
      stub_request(:get, "https://foo.bar/api/v1/namespaces/default/pods").to_raise(Net::OpenTimeout)
      e = assert_raises(RuntimeError) { process_secrets }
      e.message.must_equal("Timeout connecting to https://foo.bar/api/v1/namespaces/default/pods")
    end

    it 'raises useful debugging info when reading keys fails' do
      stub_request(:get, url).to_raise(Vault::HTTPClientError.new('http://foo.com', stub(code: 403)))
      e = assert_raises(RuntimeError) { process_secrets }
      e.message.must_include("Error reading key this/is/very/hidden")
      e.message.must_include("The Vault server at `http://foo.com'")
    end

    it 'raises useful debugging info when multiple keys fail' do
      File.write('annotations', "secret/SECRET=\"this/is/very/hidden\"\nsecret/SECRE2=\"this/is/very/secret\"")
      stub_request(:get, url).to_raise(Vault::HTTPClientError.new('http://foo.com', stub(code: 403)))
      url2 = url.sub!('very/hidden', 'very/secret') || raise
      stub_request(:get, url2).to_raise(Vault::HTTPClientError.new('http://foo.com', stub(code: 403)))
      e = assert_raises(RuntimeError) { process_secrets }
      e.message.must_include("Error reading key this/is/very/hidden")
      e.message.must_include("Error reading key this/is/very/secret")
    end

    describe 'CONSUL_URL' do
      it 'creates a CONSUL_URL secret' do
        process_secrets
        File.read("CONSUL_URL").must_equal("http://#{SecretsClient::LINK_LOCAL_IP}:8500")
      end

      it 'can be overwritten by the user' do
        File.write('annotations', "secret/CONSUL_URL=\"this/is/very/hidden\"")
        process_secrets
        File.read('CONSUL_URL').must_equal 'foo'
      end
    end

    describe 'HOST_IP' do
      it 'creates a HOST_IP secret' do
        process_secrets
        File.read("HOST_IP").must_equal("10.10.10.10")
      end

      it "raises when host ip api call fails" do
        stub_request(:get, "https://foo.bar/api/v1/namespaces/default/pods").
          to_return(status: 500)
        e = assert_raises(RuntimeError) { process_secrets }
        e.message.must_include("Could not GET https://foo.bar/api/v1/namespaces/default/pod")
      end
    end
  end

  describe '#process_pki_certs' do
    let(:certificate) { "-----BEGIN CERTIFICATE-----\nimma cert\n-----END CERTIFICATE-----" }
    let(:private_key) { "-----BEGIN RSA PRIVATE KEY-----\nimma private key\n-----END RSA PRIVATE KEY-----" }
    let(:private_key_type) { "rsa" }
    let(:issuing_ca) { "-----BEGIN CERTIFICATE-----\nimma signing cert\n-----END CERTIFICATE-----" }
    let(:chain_ca) do
      [
        "-----BEGIN CERTIFICATE-----\nchain 1\n-----END CERTIFICATE-----",
        "-----BEGIN CERTIFICATE-----\nchain 2\n-----END CERTIFICATE-----"
      ]
    end
    let(:serial_number) { "63:84:EE:63:75:65:CD:C6:BD:09:AE:A3:EB:AC:E4:50:FA:3E:D4:95" }
    let(:expiration) { "1559186544" }

    let(:reply) do
      {
        data: {
          certificate: certificate,
          private_key: private_key,
          private_key_type: private_key_type,
          issuing_ca: issuing_ca,
          chain_ca: chain_ca,
          serial_number: serial_number,
          expiration: expiration
        }
      }.to_json
    end
    let(:reply_without_chain_ca) do
      {
        data: {
          certificate: certificate,
          private_key: private_key,
          private_key_type: private_key_type,
          issuing_ca: issuing_ca,
          serial_number: serial_number,
          expiration: expiration
        }
      }.to_json
    end
    let(:url) { +'https://foo.bar:8200/v1/pki/issue/example-com' }
    let(:root_ca_url) { +'https://foo.bar:8200/v1/root-pki/issue/test-com' }
    let(:dne_url) { +'https://foo.bar:8200/v1/pki/does/not/exist' }

    before do
      stub_request(:put, url).
        with { |request| request.body == {common_name: 'example.com'}.to_json }.
        to_return(body: reply, headers: {'Content-Type': 'application/json'})

      stub_request(:put, root_ca_url).
        with { |request| request.body == {common_name: 'test.com'}.to_json }.
        to_return(body: reply_without_chain_ca, headers: {'Content-Type': 'application/json'})
    end

    it 'writes all files to the named PKI directory' do
      File.write('annotations', <<~TEXT)
        secret/SECRET="this/is/very/hidden"
        pki/example.com="pki/issue/example-com?common_name=example.com"
      TEXT

      process_pki_certs

      File.read("pki/example.com/certificate.pem").must_equal(certificate)
      File.read("pki/example.com/private_key.pem").must_equal(private_key)
      File.read("pki/example.com/private_key_type").must_equal(private_key_type)
      File.read("pki/example.com/issuing_ca.pem").must_equal(issuing_ca)
      File.read("pki/example.com/chain_ca.pem").must_equal(chain_ca.join("\n"))
      File.read("pki/example.com/serial_number").must_equal(serial_number)
      File.read("pki/example.com/expiration").must_equal(expiration)
    end

    it 'does not write chain_ca.pem if response does not contain chain_ca' do
      File.write('annotations', <<~TEXT)
        secret/SECRET="this/is/very/hidden"
        pki/test.com="root-pki/issue/test-com?common_name=test.com"
      TEXT

      process_pki_certs

      refute File.exist? "pki/test.com/chain_ca.pem"

      File.read("pki/test.com/certificate.pem").must_equal(certificate)
      File.read("pki/test.com/private_key.pem").must_equal(private_key)
      File.read("pki/test.com/private_key_type").must_equal(private_key_type)
      File.read("pki/test.com/issuing_ca.pem").must_equal(issuing_ca)
      File.read("pki/test.com/serial_number").must_equal(serial_number)
      File.read("pki/test.com/expiration").must_equal(expiration)
    end

    context 'exercise #split_url' do
      before do
        stub_request(:put, +'https://foo.bar:8200/v1/pki/issue/request-empty').
          with { |request| request.body == {}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        stub_request(:put, +'https://foo.bar:8200/v1/pki/issue/request-csv-params').
          with { |request| request.body == {ip_sans: "127.0.0.1,10.10.0.12"}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        stub_request(:put, +'https://foo.bar:8200/v1/pki/issue/request-array-params').
          with { |request| request.body == {name: ["foo", "bar"]}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})
      end

      it 'works without query params' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/request-empty"
        TEXT

        process_pki_certs
        File.read("pki/example.com/serial_number").must_equal(serial_number)
      end

      it 'works with query param csv' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/request-csv-params?ip_sans=127.0.0.1,10.10.0.12"
        TEXT

        process_pki_certs
        File.read("pki/example.com/serial_number").must_equal(serial_number)
      end

      it 'works with query param arrays' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/request-array-params?name=foo&name=bar"
        TEXT

        process_pki_certs
        File.read("pki/example.com/serial_number").must_equal(serial_number)
      end

      it 'works with multiple subdirs' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/test/example.com="pki/issue/example-com?common_name=example.com"
        TEXT

        process_pki_certs
        File.read("pki/test/example.com/serial_number").must_equal(serial_number)
      end
    end

    context 'exercise #vault_write errors' do
      before do
        stub_request(:put, url).
          with { |request| request.body == {common_name: 'fail'}.to_json }.
          to_return(body: {errors: ["common name fail not allowed by this role"]}.to_json, status: 400, headers: {'Content-Type': 'application/json'})

        stub_request(:put, dne_url).
          to_return(body: {errors: ["no handler for route 'pki/does/not/exist"]}.to_json, status: 404, headers: {'Content-Type': 'application/json'})

        stub_request(:put, +'https://foo.bar:8200/v1/nil').
          to_return(body: {data: nil}.to_json, status: 200, headers: {'Content-Type': 'application/json'})
      end

      it 'handles 404 response' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/does/not/exist"
        TEXT

        err = assert_raises Vault::HTTPClientError do
          process_pki_certs
        end
        assert_match /Error writing to pki\/does\/not\/exist/, err.message
      end

      it 'handles bad response data' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?common_name=fail"
        TEXT

        err = assert_raises Vault::HTTPClientError do
          process_pki_certs
        end
        assert_match /Error writing to pki\/issue\/example-com/, err.message
      end

      it 'handles nil response data' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="nil"
        TEXT

        err = assert_raises RuntimeError do
          process_pki_certs
        end
        assert_match /Bad results returned from vault server for nil/, err.message
      end
    end
  end
end
