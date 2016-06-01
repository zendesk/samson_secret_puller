require 'vault'

class SecretsClient

  ENCODINGS = {"/": "%2F"}
  CERT_AUTH_PATH =  '/v1/auth/cert/login'.freeze

  # auth against the server, set a token in the Vault obj
  def initialize(vault_address = nil, pemfile_path = nil, ssl_verify = false, annotations = nil, output_path = '/secrets/')
    raise "vault address not found" if vault_address.nil?
    raise "pemfile not provided" if pemfile_path.nil? || !File.exist?(pemfile_path)
    raise "path to annotations" if annotations.nil? || !File.exist?(annotations)
    @annotations = annotations
    @output_path = output_path

    pem_contents = File.read(pemfile_path)
    default_options = {
      use_ssl: true,
      verify_mode: 0,
      cert: OpenSSL::X509::Certificate.new(pem_contents),
      key: OpenSSL::PKey::RSA.new(pem_contents)
    }
    Vault.configure do |config|
      config.ssl_pem_file = pemfile_path #this is the secrets volume insde the k8s cluster
      config.ssl_verify = false #FIXME: make this ENV driven
      config.address = vault_address

      # Timeout the connection after a certain amount of time (seconds)
      config.timeout = 5

      # It is also possible to have finer-grained controls over the timeouts, these
      # may also be read as environment variables
      config.ssl_timeout  = 3
      config.open_timeout = 3
      config.read_timeout = 2
    end

    uri = URI.parse(Vault.address)
    @http = Net::HTTP.start(uri.host, uri.port, default_options)
    response = @http.request(Net::HTTP::Post.new(CERT_AUTH_PATH))
    if (response.code.to_i == 200)
      Vault.token = JSON.parse(response.body).delete("auth")["client_token"]
    else
      raise "Missing Token"
    end

    # make sure that we have secret keys
    @secret_keys = []
    IO.readlines(@annotations).each do |line|
      if line =~ /^secret\/.*$/
        key = line.split("=").first.split("/").last
        value = line.split("=").last.chomp.gsub('"','')
        @secret_keys << {"#{key}": value}
      end
    end
    raise "#{SECRET_KEY_PATH} contains no secrets" unless @secret_keys.count > 0
  end

  def process
    @secret_keys.each do |secret|
    secret.each do |name, path|
      contents = read(path)
        if contents
          File.open(@output_path + name.to_s, 'w+') { |f| f.puts contents }
        end
      end
    end
  end

  def self.vault_client
    Vault
  end

  private

  # TODO: make sure that there's enough error handling around this.
  def read(key)
    key_segments = key.split('/', 4)
    final_key = convert_path(key_segments.delete_at(3), :encode)
    key = key_segments.join('/') + '/' + final_key
    result = Vault.logical.read(vault_path(key))
    false unless result.respond_to?(:data)
    result = result.to_h
    result = result.merge(result.delete(:data))
    result.delete(:vault)
  end

  def vault_path(key)
    "secret/" + key
  end

  def convert_path(string, direction)
    string = string.dup
    if direction == :decode
      ENCODINGS.each { |k, v| string.gsub!(v.to_s, k.to_s) }
    elsif direction == :encode
      ENCODINGS.each { |k, v| string.gsub!(k.to_s, v.to_s) }
    else
      raise ArgumentError.new("direction is required")
    end
    string
  end
end

