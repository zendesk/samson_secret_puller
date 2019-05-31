# frozen_string_literal: true

require 'forwardable'

module SamsonSecretPuller
  FOLDER = '/secrets'

  ENV = ENV # store a copy since we might replace ENV on Object

  class << self
    extend Forwardable
    [
      :[], :fetch, :keys, :each, :has_key?, :key?, :include?,
      :each_with_object, :values_at, :reject, :select, :to_a
    ].each do |method|
      def_delegator :secrets, method
    end

    def to_h
      secrets.dup
    end
    alias to_hash to_h
    alias dup     to_h

    def []=(key, value)
      if value.nil?
        delete key
      elsif secrets && @secret_keys.include?(key)
        secrets[key] = value
      else
        ENV[key] = secrets[key] = value
      end
    end

    def delete(key)
      secrets.delete(key)
      ENV.delete(key)
    end

    def replace(other)
      (secrets.keys + other.keys).uniq.each { |k| self[k] = other[k] }
    end

    # When we run in kubernetes we need to read secrets from ENV and secret storage
    # but other parts of the apps or gems do not need to know about this
    def replace_ENV! # rubocop:disable Naming/MethodName
      old = $VERBOSE
      $VERBOSE = nil
      Object.const_set(:ENV, self)
    ensure
      $VERBOSE = old
    end

    private

    def secrets
      @secrets ||= begin
        combined = ENV.to_h
        secrets = read_secrets
        @secret_keys = secrets.keys
        combined.merge!(secrets)
        combined
      end
    end

    def read_secrets
      return {} unless File.exist?(FOLDER)
      Dir.glob("#{FOLDER}/*").each_with_object({}) do |file, all|
        all[File.basename(file)] = File.read(file).strip
      end
    end
  end
end
