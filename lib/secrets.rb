require 'vault'
require 'openssl'

# fixed in vault server 0.6.2 https://github.com/hashicorp/vault/pull/1795
Vault::Client.prepend(Module.new do
  def success(response)
    response.content_type = 'application/json' if response.body&.start_with?('{', '[')
    super
  end
end)

class SecretsClient
  ENCODINGS = {"/" => "%2F"}.freeze
  CERT_AUTH_PATH = '/v1/auth/cert/login'.freeze
  KEY_PARTS = 4
  LINK_LOCAL_IP = '169.254.1.1'.freeze # Kubernetes nodes are configured with this special link-local IP

  # auth against the server, set a token in the Vault obj
  def initialize(
    vault_address:, vault_mount:, vault_prefix:, vault_v2:, vault_authfile_path:,
    ssl_verify:, annotations:, serviceaccount_dir:, output_path:, api_url:
  )
    raise "vault address not found" if vault_address.nil?
    raise "authfile not found" unless File.exist?(vault_authfile_path.to_s)
    raise "annotations file not found" unless File.exist?(annotations.to_s)
    raise "serviceaccount dir #{serviceaccount_dir} not found" unless Dir.exist?(serviceaccount_dir.to_s)
    raise "api_url is null" if api_url.nil?

    @vault_mount = vault_mount
    @vault_prefix = vault_prefix
    @output_path = output_path
    @serviceaccount_dir = serviceaccount_dir
    @api_url = api_url
    @ssl_verify = ssl_verify
    @vault_v2 = vault_v2

    Vault.configure do |config|
      config.ssl_verify = ssl_verify
      config.address = vault_address
      config.ssl_timeout  = 3
      config.open_timeout = 3
      config.read_timeout = 2
    end

    Vault.token = read_vault_token(vault_authfile_path)

    @secret_keys = secrets_from_annotations(annotations)
    raise "#{annotations} contains no secrets" if @secret_keys.empty?
    log("secrets found: #{@secret_keys.join(",")}")
  end

  def write_secrets
    # Write out the pod's status.hostIP as a secret
    File.write("#{@output_path}/HOST_IP", host_ip)

    # Write out the pod's status.hostIP as a secret
    File.write("#{@output_path}/LINK_LOCAL_IP", LINK_LOCAL_IP)

    # Write out the location of consul to simplify app logic
    File.write("#{@output_path}/CONSUL_URL", "http://#{LINK_LOCAL_IP}:8500")

    # Read secrets and report all errors as one
    errors = []
    secrets = @secret_keys.map do |key, path|
      begin
        [key, read_from_vault(path)]
      rescue StandardError
        errors << $!
      end
    end

    present_errors(errors)

    # Write out user defined secrets
    secrets.each do |key, secret|
      File.write("#{@output_path}/#{key}", secret)
      log("writing secrets: #{key}")
    end

    # notify primary container that it is now safe to read all secrets
    log("all secrets written")
    File.write("#{@output_path}/.done", Time.now.to_s)
  end

  private

  def present_errors(errors)
    if errors.size == 1
      # regular error display with full backtrace
      raise errors.first
    elsif errors.size > 1
      # list all errors so users can fix multiple issues at once
      raise "Errors reading secrets:\n#{errors.map { |e| "#{e.class}: #{e.message}" }.join("\n")}"
    end
  end

  def http_post(url, pem:)
    pem_contents = File.read(pem)
    uri = URI.parse(url)
    http = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: (uri.scheme == 'https'),
      verify_mode: (@ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE),
      cert: OpenSSL::X509::Certificate.new(pem_contents),
      key: OpenSSL::PKey::RSA.new(pem_contents)
    )
    response = http.request(Net::HTTP::Post.new(uri.path))
    if response.code.to_i == 200
      response.body
    else
      raise "Could not POST #{url}: #{response.code} / #{response.body}"
    end
  end

  def http_get(url, headers:, ca_file:)
    uri = URI.parse(url)
    req = Net::HTTP::Get.new(uri.path)
    headers.each { |k, v| req.add_field(k, v) }
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.ca_file = ca_file
    http.verify_mode = (@ssl_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE)
    begin
      response = http.request(req)
    rescue Net::OpenTimeout
      raise "Timeout connecting to #{uri}"
    end
    if response.code.to_i == 200
      response.body
    else
      raise "Could not GET #{url}: #{response.code} / #{response.body}"
    end
  end

  def host_ip
    @host_ip ||= begin
      token = File.read(@serviceaccount_dir + '/token')
      namespace = File.read(@serviceaccount_dir + '/namespace')
      api_response = http_get(
        @api_url + "/api/v1/namespaces/#{namespace}/pods",
        headers: {"Authorization" => "Bearer #{token}"},
        ca_file: "#{@serviceaccount_dir}/ca.crt"
      )
      api_response = JSON.parse(api_response, symbolize_names: true)
      api_response[:items][0][:status][:hostIP].to_s
    end
  end

  def read_from_vault(key)
    key = normalize_key(key)
    begin
      result = with_retries { Vault.logical.read(vault_path(key)) }
    rescue Vault::HTTPClientError
      $!.message.prepend "Error reading key #{key}\n"
      raise
    end

    if !result.respond_to?(:data) || !result.data || !result.data.is_a?(Hash)
      raise "Bad results returned from vault server for #{key}: #{result.inspect}"
    end

    @vault_v2 ? result.data.fetch(:data).fetch(:vault) : result.data.fetch(:vault)
  end

  # keys could include slashes in last part, which we would then be unable to resolve
  # so we encode them
  def normalize_key(key)
    parts = key.split('/', KEY_PARTS)
    ENCODINGS.each { |k, v| parts.last.gsub!(k, v) }
    parts.join('/')
  end

  def vault_path(key)
    if @vault_v2
      "#{@vault_mount}/data/#{@vault_prefix}/#{key}"
    else
      "#{@vault_mount}/#{@vault_prefix}/#{key}"
    end
  end

  # secret/FOO="a/b/c/z" -> {"FOO" => "a/b/c/d"}
  def secrets_from_annotations(annotations)
    File.read(annotations).split("\n").map do |line|
      next unless line.sub! /^secret\//, ""
      key, path = line.split("=", 2)
      path.delete!('"')
      [key, path]
    end.compact
  end

  # check and see if the authfile is a pem or a token,
  # then act accordingly
  def read_vault_token(authfile_path)
    OpenSSL::X509::Certificate.new File.read(authfile_path)
    response = http_post(File.join(Vault.address, CERT_AUTH_PATH), pem: authfile_path)
    JSON.parse(response).fetch("auth").fetch("client_token")
  rescue OpenSSL::X509::CertificateError
    File.read(authfile_path)
  end

  def log(msg)
    puts "#{Time.now}: #{msg}" unless ENV["testing"]
  end

  def with_retries(&block)
    Vault.with_retries(Vault::HTTPConnectionError, attempts: 3, &block)
  end
end
