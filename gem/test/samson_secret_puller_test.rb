# frozen_string_literal: true

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
    Dir.mkdir('secrets/dir')
    File.write('secrets/FOO', 'bar')
    File.write('secrets/.done', 'd')

    # do not reuse cache
    if SamsonSecretPuller.instance_variable_defined?(:@secrets)
      SamsonSecretPuller.remove_instance_variable(:@secrets)
    end
  end

  it "ignores directories" do
    assert_nil SamsonSecretPuller['dir']
  end

  it "reads secrets" do
    assert_equal 'bar', SamsonSecretPuller['FOO']
  end

  it "fails to read missing secrets" do
    assert_nil SamsonSecretPuller['FOO2']
  end

  it "reads when folder is missing" do
    FileUtils.rm_rf("secrets")
    assert_nil SamsonSecretPuller['FOO']
  end

  it "ignores . files" do
    File.write('secrets/.done', 'bar')
    assert_nil SamsonSecretPuller['.done']
  end

  it "falls back to ENV" do
    with_env(BAR: 'foo') do
      assert_equal 'foo', SamsonSecretPuller['BAR']
    end
  end

  it "ignores .done" do
    assert_nil SamsonSecretPuller['.done']
  end

  it "overrides ENV values" do
    File.write('secrets/HOME', 'bar')
    assert_equal 'bar', SamsonSecretPuller['HOME']
  end

  describe '.fetch' do
    it "fetches secrets" do
      assert_equal 'bar', SamsonSecretPuller.fetch('FOO')
    end

    it "fails to fetches secrets" do
      assert_raises KeyError do
        SamsonSecretPuller.fetch('FOO2')
      end
    end

    it "can fallback to value" do
      assert_equal 'bar', SamsonSecretPuller.fetch('FOO2', 'bar')
    end

    it "can fallback to block" do
      assert_equal 'bar', SamsonSecretPuller.fetch('FOO2') { 'bar' }
    end
  end

  describe '.keys' do
    it "lists secret and env keys" do
      assert_includes SamsonSecretPuller.keys, 'FOO'
      assert_includes SamsonSecretPuller.keys, 'HOME'
    end
  end

  describe '.to_h' do
    it "generates a complete hash" do
      assert_equal "bar", SamsonSecretPuller.to_h["FOO"]
    end

    it "generates a copy" do
      SamsonSecretPuller.to_h["FOO"] = "baz"
      assert_equal "bar", SamsonSecretPuller.to_h["FOO"]
    end
  end

  describe '.replace' do
    it "replaces secrets but does not expose them to ENV since users most likely use .to_h for the input" do
      begin
        old = ENV.to_h
        with_env "BAR" => "baz" do
          SamsonSecretPuller.replace("FOO" => "BAR", "BAR" => "update")
          assert_equal "BAR", SamsonSecretPuller["FOO"]
          assert_equal "update", SamsonSecretPuller["BAR"]
          assert_nil ENV["FOO"]
          assert_equal "update", ENV["BAR"]
        end
      ensure
        ENV.replace(old)
      end
    end
  end

  describe '.to_a' do
    it "works" do
      assert_includes SamsonSecretPuller.to_a, ["FOO", "bar"]
    end
  end

  describe '.to_hash' do
    it "generates a complete hash" do
      assert_equal "bar", SamsonSecretPuller.to_hash["FOO"]
    end

    it "generates a copy" do
      SamsonSecretPuller.to_hash["FOO"] = "baz"
      assert_equal "bar", SamsonSecretPuller.to_hash["FOO"]
    end
  end

  describe '.dup' do
    it "generates a complete hash" do
      assert_equal "bar", SamsonSecretPuller.dup["FOO"]
    end

    it "generates a copy" do
      new_version = SamsonSecretPuller.dup
      new_version["FOO"] = "baz"
      assert_equal "bar", SamsonSecretPuller["FOO"]
    end
  end

  describe '[]=' do
    it "writes into the environment and secrets" do
      SamsonSecretPuller["BAR"] = 'baz'
      assert_equal 'baz', ENV["BAR"]
      assert_equal 'baz', SamsonSecretPuller["BAR"]
    end

    it "deletes when setting nil" do
      SamsonSecretPuller["BAR"] = nil
      assert_equal false, ENV.key?("BAR")
      assert_equal false, SamsonSecretPuller.key?("BAR")
    end

    it "does not write secrets to disk/process" do
      SamsonSecretPuller["FOO"] = "baz"
      assert_equal "baz", SamsonSecretPuller["FOO"]
      assert_nil ENV["FOO"]
    end
  end

  describe '.each' do
    it "iterates all" do
      found = []
      SamsonSecretPuller.each { |k, v| found << [k, v] }
      assert_includes found, ["FOO", "bar"]
      assert_includes found, ["HOME", ENV["HOME"]]
    end
  end

  describe '.delete' do
    it "deletes secrets and env" do
      ENV['FOO'] = 'bar'
      assert_equal 'bar', SamsonSecretPuller.delete('FOO')
      assert_nil SamsonSecretPuller.delete('FOO')
      assert_nil ENV['FOO']
    end
  end

  describe '.each_with_object' do
    it "iterates" do
      result = SamsonSecretPuller.each_with_object([]) { |(k, _), a| a << k }
      assert_equal SamsonSecretPuller.keys, result
    end
  end

  describe '.values_at' do
    it "works" do
      result = SamsonSecretPuller.values_at('FOO')
      assert_equal ['bar'], result
    end
  end

  describe '.reject / .select' do
    it "works" do
      assert_equal({ 'FOO' => 'bar' }, SamsonSecretPuller.select { |k, _| k == 'FOO' })
      assert_equal({ 'FOO' => 'bar' }, SamsonSecretPuller.reject { |k, _| k != 'FOO' })
    end
  end

  describe '.replace_ENV!' do
    it "replaces the ENV" do
      silence_warnings { SamsonSecretPuller.const_set(:Object, Class.new) }
      SamsonSecretPuller.replace_ENV!
      assert_equal SamsonSecretPuller, SamsonSecretPuller::Object::ENV
      assert_equal "bar", SamsonSecretPuller::Object::ENV["FOO"]
    end
  end

  it "can load without bundler" do
    file = Bundler.root.join('gem/lib/samson_secret_puller')
    Bundler.with_unbundled_env do
      assert_equal "1\n", `ruby -r#{file} -e 'puts 1' 2>&1`
    end
  end
end
