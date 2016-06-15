require_relative 'test_helper'
require 'open-uri'
require 'timeout'
require 'rack'

describe "CLI" do
  class FakeServer
    TEST_ENDPOINT = "/__ping__".freeze

    def self.open(port, replies)
      server = new(port, replies)
      server.boot
      server.wait
      yield server
    ensure
      server.shutdown
    end

    def initialize(port, replies)
      @port = port
      @replies = replies
    end

    def boot
      Thread.new do
        Rack::Handler::WEBrick.run(
          self,
          Port: @port,
          Logger: WEBrick::Log.new("/dev/null"),
          AccessLog: []
        ) { |s| @server = s }
      end
    end

    def wait
      Timeout.timeout(10) do
        loop do
          begin
            socket = TCPSocket.new('localhost', @port)
            socket.close if socket
            return
          rescue Errno::ECONNREFUSED
          end
        end
      end
    end

    def call(env)
      path = env.fetch("PATH_INFO")
      unless reply = @replies[path]
        puts "Missing reply for path #{path}" # kubeclient does not show current url when failing
        raise
      end
      [200, {'Content-Type' => 'application/json'}, [reply.to_json]]
    end

    def shutdown
      @server.shutdown if @server
    end
  end

  def with_env(env)
    old = env.keys.map { |k| [k, ENV[k.to_s]] }
    env.each { |k, v| ENV[k.to_s] = v }
    yield
  ensure
    old.each { |k, v| ENV[k.to_s] = v }
  end

  def sh(command)
    result = `#{command} 2>&1`
    raise "FAILED #{result}" unless $?.success?
    result
  end

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

    FakeServer.open(8211, replies) do
      with_env(
        TESTING: 'true',
        VAULT_ADDR: 'http://localhost:8211',
        VAULT_AUTH_PEM: 'pem',
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
