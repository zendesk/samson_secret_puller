module SamsonSecretPuller
  FOLDER = '/secrets'.freeze
  TIMEOUT = 60

  class TimeoutError < StandardError
  end

  ENV = ENV # store a copy since we might replace ENV on Object

  class << self
    extend Forwardable
    [:[], :fetch, :keys, :each, :include?, :delete, :each_with_object, :values_at].each do |method|
      def_delegator :secrets, method
    end

    def []=(key, value)
      ENV[key] = secrets[key] = value
    end

    def to_h
      secrets
    end

    # When we run in kubernetes we need to read secrets from ENV and secret storage
    # but other parts of the apps or gems do not need to know about this
    def replace_ENV! # rubocop:disable Style/MethodName
      old = $VERBOSE
      $VERBOSE = nil
      Object.const_set(:ENV, self)
    ensure
      $VERBOSE = old
    end

    private

    def secrets
      @secrets ||= begin
        secrets = ENV.to_h

        if File.exist?(FOLDER)
          wait_for_secrets_to_appear
          merge_secrets(secrets)
        end

        secrets
      end
    end

    def merge_secrets(secrets)
      Dir.glob("#{FOLDER}/*").each do |file|
        name = File.basename(file)
        next if name.start_with?(".") # ignore .done and maybe others
        secrets[name] = File.read(file).strip
      end
    end

    def wait_for_secrets_to_appear
      start = Time.now
      done_file = "#{FOLDER}/.done"
      # secrets should appear in that folder any second now
      until File.exist?(done_file)
        if Time.now > start + TIMEOUT
          raise TimeoutError, "Waited #{TIMEOUT} seconds for #{done_file} to appear."
        else
          warn 'waiting for secrets to appear'
          sleep 0.1
        end
      end
    end
  end
end
