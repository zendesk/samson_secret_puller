require_relative 'test_helper'
require_relative '../lib/samson_secret_puller'
require 'tmpdir'
require 'timeout'

SingleCov.covered!

describe SamsonSecretPuller do
  def silence_warnings
    old = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = old
  end

  def with_env(env)
    old = env.map do |k, v|
      k = k.to_s
      o = ENV[k]
      ENV[k] = v
      [k, o]
    end
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end

  def capture_stderr
    old = STDERR
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old
  end

  def change_constant(constant_name, value)
    old = SamsonSecretPuller.const_get(constant_name)
    silence_warnings { SamsonSecretPuller.const_set(constant_name, value) }
    yield
  ensure
    silence_warnings { SamsonSecretPuller.const_set(constant_name, old) }
  end

  around { |t| Dir.mktmpdir { |d| Dir.chdir(d) { t.call } } }
  around { |t| change_constant :FOLDER, 'secrets', &t }
  around { |t| Timeout.timeout(2) { t.call } } # make sure tests do not hang

  before do
    # basic healthy status
    Dir.mkdir('secrets')
    File.write('secrets/FOO', 'bar')
    File.write('secrets/.done', 'd')

    # do not reuse cache
    if SamsonSecretPuller.instance_variable_defined?(:@secrets)
      SamsonSecretPuller.remove_instance_variable(:@secrets)
    end
  end

  it "reads secrets" do
    SamsonSecretPuller['FOO'].must_equal 'bar'
  end

  it "fails to read secrets" do
    SamsonSecretPuller['FOO2'].must_be_nil
  end

  it "falls back to ENV" do
    with_env(BAR: 'foo') do
      SamsonSecretPuller['BAR'].must_equal 'foo'
    end
  end

  it "ignores .done" do
    SamsonSecretPuller['.done'].must_be_nil
  end

  it "overrides ENV values" do
    File.write('secrets/HOME', 'bar')
    SamsonSecretPuller['HOME'].must_equal 'bar'
  end

  describe '.fetch' do
    it "fetches secrets" do
      SamsonSecretPuller.fetch('FOO').must_equal 'bar'
    end

    it "fails to fetches secrets" do
      assert_raises KeyError do
        SamsonSecretPuller.fetch('FOO2')
      end
    end

    it "can fallback to value" do
      SamsonSecretPuller.fetch('FOO2', 'bar').must_equal 'bar'
    end

    it "can fallback to block" do
      SamsonSecretPuller.fetch('FOO2') { 'bar' }.must_equal 'bar'
    end
  end

  describe '.keys' do
    it "lists secret and env keys" do
      SamsonSecretPuller.keys.must_include 'FOO'
      SamsonSecretPuller.keys.must_include 'HOME'
    end
  end

  describe '.to_h' do
    it "generates a complete hash" do
      SamsonSecretPuller.to_h["FOO"].must_equal "bar"
    end

    it "generates a copy" do
      SamsonSecretPuller.to_h["FOO"] = "baz"
      SamsonSecretPuller.to_h["FOO"].must_equal "bar"
    end
  end

  describe '.replace' do
    it "replaces secrets but does not expose them to ENV since users most likely use .to_h for the input" do
      begin
        old = ENV.to_h
        with_env "BAR" => "baz" do
          SamsonSecretPuller.replace("FOO" => "BAR", "BAR" => "update")
          SamsonSecretPuller["FOO"].must_equal "BAR"
          SamsonSecretPuller["BAR"].must_equal "update"
          ENV["FOO"].must_be_nil
          ENV["BAR"].must_equal "update"
        end
      ensure
        ENV.replace(old)
      end
    end
  end

  describe '.to_a' do
    it "works" do
      SamsonSecretPuller.to_a.must_include ["FOO", "bar"]
    end
  end

  describe '.to_hash' do
    it "generates a complete hash" do
      SamsonSecretPuller.to_hash["FOO"].must_equal "bar"
    end

    it "generates a copy" do
      SamsonSecretPuller.to_hash["FOO"] = "baz"
      SamsonSecretPuller.to_hash["FOO"].must_equal "bar"
    end
  end

  describe '.dup' do
    it "generates a complete hash" do
      SamsonSecretPuller.dup["FOO"].must_equal "bar"
    end

    it "generates a copy" do
      new_version = SamsonSecretPuller.dup
      new_version["FOO"] = "baz"
      SamsonSecretPuller["FOO"].must_equal "bar"
    end
  end

  describe '[]=' do
    it "writes into the environment and secrets" do
      SamsonSecretPuller["BAR"] = 'baz'
      ENV["BAR"].must_equal 'baz'
      SamsonSecretPuller["BAR"].must_equal 'baz'
    end

    it "deletes when setting nil" do
      SamsonSecretPuller["BAR"] = nil
      ENV.key?("BAR").must_equal false
      SamsonSecretPuller.key?("BAR").must_equal false
    end

    it "does not write secrets to disk/process" do
      SamsonSecretPuller["FOO"] = "baz"
      SamsonSecretPuller["FOO"].must_equal "baz"
      ENV["FOO"].must_be_nil
    end
  end

  describe '.each' do
    it "iterates all" do
      found = []
      SamsonSecretPuller.each { |k, v| found << [k, v] }
      found.must_include ["FOO", "bar"]
      found.must_include ["HOME", ENV["HOME"]]
    end
  end

  describe '.delete' do
    it "deletes secrets and env" do
      ENV['FOO'] = 'bar'
      SamsonSecretPuller.delete('FOO').must_equal 'bar'
      SamsonSecretPuller.delete('FOO').must_be_nil
      ENV['FOO'].must_be_nil
    end
  end

  describe '.each_with_object' do
    it "iterates" do
      result = SamsonSecretPuller.each_with_object([]) { |(k, _), a| a << k }
      result.must_equal SamsonSecretPuller.keys
    end
  end

  describe '.values_at' do
    it "works" do
      result = SamsonSecretPuller.values_at('FOO')
      result.must_equal(['bar'])
    end
  end

  describe '.reject / .select' do
    it "works" do
      SamsonSecretPuller.select { |k, _| k == 'FOO' }.must_equal 'FOO' => 'bar'
      SamsonSecretPuller.reject { |k, _| k != 'FOO' }.must_equal 'FOO' => 'bar' # rubocop:disable Style/InverseMethods
    end
  end

  describe '.replace_ENV!' do
    it "replaces the ENV" do
      silence_warnings { SamsonSecretPuller.const_set(:Object, Class.new) }
      SamsonSecretPuller.replace_ENV!
      SamsonSecretPuller::Object::ENV.must_equal SamsonSecretPuller
      SamsonSecretPuller::Object::ENV["FOO"].must_equal "bar"
    end
  end

  it "can load without bundler" do
    file = Bundler.root.join('gem/lib/samson_secret_puller')
    Bundler.with_clean_env do
      `ruby -r#{file} -e 'puts 1' 2>&1`.must_equal "1\n"
    end
  end
end
