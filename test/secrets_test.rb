# frozen_string_literal: true

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
      serviceaccount_dir: 'foo',
      output_path: Dir.pwd,
      api_url: 'https://foo.bar',
      vault_v2: false,
      pod_hostname: 'example.com',
      logger: logger
    }
  end
  let(:logger) { Logger.new(STDOUT) }
  let(:token_client) { SecretsClient.new(client_options) }
  let(:serviceaccount_client) do
    client_options[:vault_auth_type] = "kubernetes"
    client_options[:serviceaccount_dir] = Dir.pwd
    SecretsClient.new(client_options)
  end
  let(:client) do
    client_options[:vault_auth_type] = "cert"
    client_options[:vault_authfile_path] = "vaultpem"
    SecretsClient.new(client_options)
  end
  let(:auth_reply) { {auth: {client_token: 'sometoken'}}.to_json }
  let(:token_reply) { { data: {id: 'sometoken'}}.to_json }
  let(:status_api_body) { {items: [{status: {hostIP: "10.10.10.10"}}]}.to_json }

  before do
    logger.stubs(:debug)
    stub_request(:post, "https://foo.bar:8200/v1/auth/cert/login").
      to_return(response_body(auth_reply))
    stub_request(:get, "https://foo.bar:8200/v1/auth/token/lookup-self").
      to_return(response_body(token_reply))
  end

  around do |test|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("vaultpem", File.read(Bundler.root.join("test/fixtures/self_signed_testing.pem")))
        File.write("ca.crt", File.read(Bundler.root.join("test/fixtures/self_signed_testing.pem")))
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

    it "works with a serviceaccount" do
      stub_request(:post, "https://foo.bar:8200/v1/auth/kubernetes/login").
        to_return(response_body(auth_reply))
      serviceaccount_client
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
      assert_raises(ArgumentError) { client }
    end

    it "fails to initialize with invalid type" do
      assert_raises(ArgumentError) { SecretsClient.new(client_options.merge(vault_auth_type: "foobar")) }
    end

    it "fails to initialize without url" do
      assert_raises(ArgumentError) { SecretsClient.new(client_options.merge(vault_address: nil)) }
    end

    it "fails to initialize without api_url" do
      assert_raises(ArgumentError) { SecretsClient.new(client_options.merge(api_url: nil)) }
    end

    it "fails to initialize when serviceaccount_dir is missing" do
      assert_raises(ArgumentError) do
        SecretsClient.new(client_options.merge(serviceaccount_dir: "foo", vault_auth_type: "kubernetes"))
      end
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
      assert_equal "foo", File.read("SECRET")
    end

    it 'logs' do
      logger.unstub(:debug)
      logger.expects(:debug).with(message: "Authenticated with Vault Server", policies: nil, metadata: nil)
      logger.expects(:debug).with(message: "secrets found", keys: [["SECRET", "this/is/very/hidden"]])
      logger.expects(:debug).with(message: "PKI found", keys: [])
      process_secrets
    end

    it 'ignores newline in key name' do
      File.write('annotations', File.read('annotations') + "\n")
      process_secrets
      assert_equal "foo", File.read("SECRET")
    end

    it 'ignores = in path' do
      url.sub!('hidden', 'hi=dden') || raise
      request = stub_request(:get, url).to_return(response_body({data: {vault: 'foo'}}.to_json))
      File.write('annotations', File.read('annotations').sub!("hidden", "hi=dden"))

      process_secrets

      assert_equal "foo", File.read("SECRET")
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

      assert_equal "foo", File.read("SECRET")
      assert_requested request
    end

    it 'raises when no secrets were used' do
      File.write('annotations', "other-annotation=\"this/is/not/hidden\"")
      assert_raises(ArgumentError) { process_secrets }
      refute File.exist?("SECRET")
    end

    it "raises when response is invalid" do
      reply.replace({foo: {bar: 1}}.to_json)
      assert_raises(RuntimeError) { process_secrets }
    end

    it "raises when response is not 200" do
      stub_request(:post, "https://foo.bar:8200/v1/auth/cert/login").
        to_return(status: 500, body: { errors: ["sample error"]}.to_json)
      e = assert_raises(Vault::HTTPError) { process_secrets }
      assert_includes e.message, "sample error"
      assert_includes e.message, "The Vault server at `https://foo.bar:8200'"
    end

    it 'raises useful debugging info when reading keys fails' do
      stub_request(:get, url).to_raise(Vault::HTTPClientError.new('http://foo.com', stub(code: 403)))
      e = assert_raises(RuntimeError) { process_secrets }
      assert_includes e.message, "Error reading key this/is/very/hidden"
      assert_includes e.message, "The Vault server at `http://foo.com'"
    end

    it 'raises useful debugging info when multiple keys fail' do
      File.write('annotations', "secret/SECRET=\"this/is/very/hidden\"\nsecret/SECRE2=\"this/is/very/secret\"")
      stub_request(:get, url).to_raise(Vault::HTTPClientError.new('http://foo.com', stub(code: 403)))
      url2 = url.sub!('very/hidden', 'very/secret') || raise
      stub_request(:get, url2).to_raise(Vault::HTTPClientError.new('http://foo.com', stub(code: 403)))
      e = assert_raises(RuntimeError) { process_secrets }
      assert_includes e.message, "Error reading key this/is/very/hidden"
      assert_includes e.message, "Error reading key this/is/very/secret"
    end

    describe 'LINK_LOCAL_IP' do
      it 'creates a LINK_LOCAL_IP secret' do
        process_secrets
        assert_equal SecretsClient::LINK_LOCAL_IP, File.read("LINK_LOCAL_IP")
      end
    end

    describe 'CONSUL_URL' do
      it 'creates a CONSUL_URL secret' do
        process_secrets
        assert_equal "http://#{SecretsClient::LINK_LOCAL_IP}:8500", File.read("CONSUL_URL")
      end

      it 'can be overwritten by the user' do
        File.write('annotations', "secret/CONSUL_URL=\"this/is/very/hidden\"")
        process_secrets
        assert_equal 'foo', File.read('CONSUL_URL')
      end
    end
  end

  describe '#process_pki_certs' do
    let(:certificate) { "-----BEGIN CERTIFICATE-----\nimma cert\n-----END CERTIFICATE-----" }
    let(:private_key) { "-----BEGIN RSA PRIVATE KEY-----\nimma private key\n-----END RSA PRIVATE KEY-----" }
    let(:private_key_type) { "rsa" }
    let(:issuing_ca) { "-----BEGIN CERTIFICATE-----\nimma signing cert\n-----END CERTIFICATE-----" }
    let(:ca_chain) do
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
          ca_chain: ca_chain,
          serial_number: serial_number,
          expiration: expiration
        }
      }.to_json
    end
    let(:reply_without_ca_chain) do
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
        to_return(body: reply_without_ca_chain, headers: {'Content-Type': 'application/json'})
    end

    it 'writes all files to the named PKI directory' do
      File.write('annotations', <<~TEXT)
        secret/SECRET="this/is/very/hidden"
        pki/example.com="pki/issue/example-com?common_name=example.com"
      TEXT

      process_pki_certs

      assert_equal certificate, File.read("pki/example.com/certificate.pem")
      assert_equal private_key, File.read("pki/example.com/private_key.pem")
      assert_equal private_key_type, File.read("pki/example.com/private_key_type")
      assert_equal issuing_ca, File.read("pki/example.com/issuing_ca.pem")
      assert_equal ca_chain.join("\n"), File.read("pki/example.com/ca_chain.pem")
      assert_equal serial_number, File.read("pki/example.com/serial_number")
      assert_equal expiration, File.read("pki/example.com/expiration")
    end

    it 'does not write ca_chain.pem if response does not contain ca_chain' do
      File.write('annotations', <<~TEXT)
        secret/SECRET="this/is/very/hidden"
        pki/test.com="root-pki/issue/test-com?common_name=test.com"
      TEXT

      process_pki_certs

      refute File.exist? "pki/test.com/ca_chain.pem"

      assert_equal certificate, File.read("pki/test.com/certificate.pem")
      assert_equal private_key, File.read("pki/test.com/private_key.pem")
      assert_equal private_key_type, File.read("pki/test.com/private_key_type")
      assert_equal issuing_ca, File.read("pki/test.com/issuing_ca.pem")
      assert_equal serial_number, File.read("pki/test.com/serial_number")
      assert_equal expiration, File.read("pki/test.com/expiration")
    end

    it 'does nothing without keys' do
      File.write('annotations', <<~TEXT)
        secret/SECRET="this/is/very/hidden"
      TEXT
      process_pki_certs
    end

    context 'exercise #split_url' do
      before do
        stub_request(:put, +'https://foo.bar:8200/v1/pki/issue/request-empty').
          with { |request| request.body == {}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        stub_request(:put, +'https://foo.bar:8200/v1/pki/issue/request-csv-params').
          with { |request| request.body == {ip_sans: "127.0.0.1,10.10.0.12"}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})
      end

      it 'works without query params' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/request-empty"
        TEXT

        process_pki_certs
        assert_equal serial_number, File.read("pki/example.com/serial_number")
      end

      it 'works with query param csv' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/request-csv-params?ip_sans=127.0.0.1,10.10.0.12"
        TEXT

        process_pki_certs
        assert_equal serial_number, File.read("pki/example.com/serial_number")
      end

      it 'works with multiple subdirs' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/test/example.com="pki/issue/example-com?common_name=example.com"
        TEXT

        process_pki_certs
        assert_equal serial_number, File.read("pki/test/example.com/serial_number")
      end
    end

    context 'exercise #vault_write errors' do
      before do
        stub_request(:put, url).
          with { |request| request.body == {common_name: 'fail'}.to_json }.
          to_return(
            body: {errors: ["common name fail not allowed by this role"]}.to_json,
            status: 400,
            headers: {'Content-Type': 'application/json'}
          )

        stub_request(:put, dne_url).
          to_return(
            body: {errors: ["no handler for route 'pki/does/not/exist"]}.to_json,
            status: 404,
            headers: {'Content-Type': 'application/json'}
          )

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

    context 'exercise pod data injection' do
      it 'includes pod ip address in cert issue request' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?common_name=example.com&pod_ip_as_san=true"
        TEXT

        stub_req = stub_request(:put, url).
          with { |request| request.body == {common_name: 'example.com', ip_sans: '127.0.0.1'}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        sc = SecretsClient.new(client_options.merge(pod_ip: '127.0.0.1'))
        sc.write_pki_certs

        assert_requested stub_req
      end

      it 'processes ip_sans csv input and includes pod ip address in cert issue request' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?common_name=example.com&pod_ip_as_san=true&ip_sans=10.10.10.10,12.12.12.12"
        TEXT

        stub_req = stub_request(:put, url).
          with do |request|
            request.body == {common_name: 'example.com', ip_sans: '127.0.0.1,10.10.10.10,12.12.12.12'}.to_json
          end.to_return(body: reply, headers: {'Content-Type': 'application/json'})

        sc = SecretsClient.new(client_options.merge(pod_ip: '127.0.0.1'))
        sc.write_pki_certs

        assert_requested stub_req
      end

      it 'processes ip_sans array and includes pod ip address in cert issue request' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?common_name=example.com&pod_ip_as_san=true&ip_sans=10.10.10.10&ip_sans=12.12.12.12"
        TEXT

        stub_req = stub_request(:put, url).
          with do |request|
            request.body == {common_name: 'example.com', ip_sans: '127.0.0.1,10.10.10.10,12.12.12.12'}.to_json
          end.to_return(body: reply, headers: {'Content-Type': 'application/json'})

        sc = SecretsClient.new(client_options.merge(pod_ip: '127.0.0.1'))
        sc.write_pki_certs

        assert_requested stub_req
      end

      it 'skips including pod IP in cert request' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?common_name=example.com&pod_ip_as_san=true
        TEXT

        stub_req = stub_request(:put, url).
          with { |request| request.body == {common_name: 'example.com', ip_sans: '127.0.0.1'}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        sc = SecretsClient.new(client_options.merge(pod_ip: '127.0.0.1'))
        sc.write_pki_certs

        assert_requested stub_req
      end

      it 'includes pod hostname as common name in cert issue request' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?pod_hostname_as_cn=true"
        TEXT

        stub_req = stub_request(:put, url).
          with { |request| request.body == {common_name: 'test'}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        sc = SecretsClient.new(client_options.merge(pod_hostname: 'test'))
        sc.write_pki_certs

        assert_requested stub_req
      end

      it 'overrides pod hostname as common name in cert issue request' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?common_name=example.com&pod_hostname_as_cn=true"
        TEXT

        stub_req = stub_request(:put, url).
          with { |request| request.body == {common_name: 'test'}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        sc = SecretsClient.new(client_options.merge(pod_hostname: 'test'))
        sc.write_pki_certs

        assert_requested stub_req
      end

      it 'includes pod hostname as alternate name in cert issue request' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?common_name=example.com&pod_hostname_as_san=true"
        TEXT

        stub_req = stub_request(:put, url).
          with { |request| request.body == {common_name: 'example.com', alt_names: 'test'}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        sc = SecretsClient.new(client_options.merge(pod_hostname: 'test'))
        sc.write_pki_certs

        assert_requested stub_req
      end

      it 'processes alt names csv input and includes pod hostname as alt name in cert issue request' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?common_name=example.com&alt_names=foo.bar,cert.me&pod_hostname_as_san=true"
        TEXT

        stub_req = stub_request(:put, url).
          with { |request| request.body == {common_name: 'example.com', alt_names: 'test,foo.bar,cert.me'}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        sc = SecretsClient.new(client_options.merge(pod_hostname: 'test'))
        sc.write_pki_certs

        assert_requested stub_req
      end

      it 'processes alt names array and includes pod hostname as alt name in cert issue request' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?common_name=example.com&alt_names=foo.bar&alt_names=cert.me&pod_hostname_as_san=true"
        TEXT

        stub_req = stub_request(:put, url).
          with { |request| request.body == {common_name: 'example.com', alt_names: 'test,foo.bar,cert.me'}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        sc = SecretsClient.new(client_options.merge(pod_hostname: 'test'))
        sc.write_pki_certs

        assert_requested stub_req
      end

      it 'is another test' do
        File.write('annotations', <<~TEXT)
          secret/SECRET="this/is/very/hidden"
          pki/example.com="pki/issue/example-com?common_name=example.com&alt_names=foo.bar&pod_hostname_as_san=true"
        TEXT

        stub_req = stub_request(:put, url).
          with { |request| request.body == {common_name: 'example.com', alt_names: 'test,foo.bar'}.to_json }.
          to_return(body: reply, headers: {'Content-Type': 'application/json'})

        sc = SecretsClient.new(client_options.merge(pod_hostname: 'test'))
        sc.write_pki_certs

        assert_requested stub_req
      end
    end
  end

  describe '#read_from_vault' do
    def stub_read
      stub_request(:get, "https://foo.bar:8200/v1/secret/apps/foo")
    end

    let(:valid) { {body: {data: {vault: "bar"}}.to_json, headers: {'Content-Type': 'application/json'}} }

    before { client.stubs(:sleep).with { false } }

    it 'reads' do
      request = stub_read.to_return(valid)
      assert_equal "bar", client.send(:read_from_vault, 'foo')
      assert_requested request, times: 1
    end

    it 'retries on 429' do
      client.expects(:sleep).times(1)
      request = stub_read.to_return({status: 429}, valid)
      assert_equal "bar", client.send(:read_from_vault, 'foo')
      assert_requested request, times: 2
    end

    it 'does not retry on regular errors' do
      request = stub_read.to_return(status: 500)
      message = assert_raises Vault::HTTPServerError do
        client.send(:read_from_vault, 'foo')
      end.message
      assert_match /\AThe Vault server at/, message
      assert_requested request, times: 1
    end

    it 'does not retry forever' do
      client.expects(:sleep).times(4)
      request = stub_read.to_return(status: 429)
      message = assert_raises Vault::HTTPClientError do
        client.send(:read_from_vault, 'foo')
      end.message
      assert_match /\AError reading key foo\n/, message
      assert_requested request, times: 5
    end
  end
end
