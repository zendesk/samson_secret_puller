require 'bundler/setup'

require 'single_cov'
SingleCov.setup :minitest

require 'maxitest/autorun'
require 'webmock/minitest'
require 'tmpdir'

def root
  Bundler.root.to_s
end

Thread.abort_on_exception = true

Minitest::Test.class_eval do
  def with_env(env)
    old = env.keys.map { |k| [k, ENV[k.to_s]] }
    env.each { |k, v| ENV[k.to_s] = v }
    yield
  ensure
    old.each { |k, v| ENV[k.to_s] = v }
  end

  def sh(command, fail: false)
    result = `#{command} 2>&1`
    raise "FAILED #{result}" if $?.success? == fail
    result
  end
end

class FakeServer
  def self.open(port, replies)
    server = new(port, replies)
    server.boot
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
      puts "ERROR: Missing reply for path #{path}" # kubeclient does not show current url when failing
      raise
    end
    [200, {'Content-Type' => 'application/json'}, [reply.to_json]]
  end

  def shutdown
    @server.shutdown if @server
  end
end
