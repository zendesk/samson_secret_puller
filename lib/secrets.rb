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
  KEY_PARTS = 4
  LINK_LOCAL_IP = '169.254.1.1'.freeze # Kubernetes nodes are configured with this special link-local IP

  # auth against the server, set a token in the Vault obj
  def initialize(
    vault_address:, vault_mount:, vault_prefix:, vault_v2:,
    ssl_verify:, annotations:, serviceaccount_dir:, output_path:, api_url:, logger:,
    vault_auth_type: 'token', vault_auth_path: nil, vault_auth_role: nil, vault_authfile_path: nil
  )
    raise "vault address not found" if vault_address.nil?
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
    @logger = logger

    @vault = Vault::Client.new(
      ssl_verify: ssl_verify,
      address: vault_address,
      ssl_timeout: 3,
      open_timeout: 3,
      read_timeout: 2
    )

    @vault.with_retries(Vault::HTTPConnectionError, attempts: 3) do
      authenticate_vault(
        @vault,
        vault_auth_type: vault_auth_type,
        vault_auth_path: vault_auth_path,
        vault_authfile_path: vault_authfile_path,
        vault_auth_role: vault_auth_role
      )
    end

    @secret_keys = secrets_from_annotations(annotations)
    raise "#{annotations} contains no secrets" if @secret_keys.empty?
    @logger.info(message: "secrets found", keys: @secret_keys)
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
    end

    # notify primary container that it is now safe to read all secrets
    File.write("#{@output_path}/.done", Time.now.to_s)
    @logger.info(message: "secrets written")
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

  def serviceaccount_token
    @serviceaccount_token ||= File.read(@serviceaccount_dir + '/token')
  end

  def host_ip
    @host_ip ||= begin
      namespace = File.read(@serviceaccount_dir + '/namespace')
      api_response = http_get(
        @api_url + "/api/v1/namespaces/#{namespace}/pods",
        headers: {"Authorization" => "Bearer #{serviceaccount_token}"},
        ca_file: "#{@serviceaccount_dir}/ca.crt"
      )
      api_response = JSON.parse(api_response, symbolize_names: true)
      api_response[:items][0][:status][:hostIP].to_s
    end
  end

  def read_from_vault(key)
    key = normalize_key(key)
    begin
      result = @vault.with_retries(Vault::HTTPConnectionError, attempts: 3) do
        @vault.logical.read(vault_key_path(key))
      end
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

  def vault_key_path(key)
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

  def authenticate_vault(client, vault_auth_type:, vault_auth_path: nil, vault_auth_role: nil, vault_authfile_path: nil)
    vault_auth_path ||= vault_auth_type

    case vault_auth_type
    when 'kubernetes'
      # https://www.vaultproject.io/api/auth/kubernetes/index.html#login
      payload = { role: vault_auth_role, jwt: serviceaccount_token }
      json = client.post("/v1/auth/#{vault_auth_path}/login", JSON.fast_generate(payload))
    when 'cert'
      raise "authfile not found" unless File.exist?(vault_authfile_path.to_s)
      new_client = client.dup
      new_client.ssl_pem_file = vault_authfile_path
      json = new_client.post("/v1/auth/#{vault_auth_path}/login")
    when 'token'
      raise "authfile not found" unless File.exist?(vault_authfile_path.to_s)
      client.token = File.read(vault_authfile_path)
      json = client.get("/v1/auth/token/lookup-self")
    else
      raise "Unsupported Vault Auth Type: #{vault_auth_type}"
    end

    secret = Vault::Secret.decode(json)
    if vault_auth_type == "token"
      auth_data = Vault::SecretAuth.decode(secret.data)
    else
      auth_data = secret.auth
      client.token = secret.auth.client_token
    end

    @logger.info(message: "Authenticated with Vault Server", policies: auth_data.policies, metadata: auth_data.metadata)
  end
end
