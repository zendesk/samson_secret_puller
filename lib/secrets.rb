# frozen_string_literal: true

require 'vault'
require 'openssl'
require 'fileutils'
require 'socket'

# fixed in vault server 0.6.2 https://github.com/hashicorp/vault/pull/1795
Vault::Client.prepend(Module.new do
  def success(response)
    response.content_type = 'application/json' if response.body&.start_with?('{', '[') # uncovered
    super
  end
end)

class SecretsClient
  ENCODINGS = {"/" => "%2F"}.freeze
  KEY_PARTS = 4
  LINK_LOCAL_IP = '169.254.1.1' # Kubernetes nodes are configured with this special link-local IP

  # auth against the server, set a token in the Vault obj
  def initialize(
    vault_address:, vault_mount:, vault_prefix:, vault_v2:,
    ssl_verify:, annotations:, env_secrets_prefix:, env_pki_prefix:, serviceaccount_dir:, output_path:,
    api_url:, logger:, vault_auth_type: 'token', vault_auth_path: nil, vault_auth_role: nil,
    vault_authfile_path: nil, pod_ip: nil, pod_hostname: nil
  )
    raise ArgumentError, "vault address not found" if vault_address.nil?
    if File.exist?(annotations.to_s) && (!env_secrets_prefix.nil? || !env_pki_prefix.nil?)
      raise ArgumentError, "can't specify both annotations file and env/pki prefixs"
    elsif !File.exist?(annotations.to_s) && (env_secrets_prefix.nil? || env_pki_prefix.nil?)
      raise ArgumentError, "must specify either annotations file or env/pki prefixs"
    elsif !File.exist?(annotations.to_s) && (env_secrets_prefix.nil? || env_pki_prefix.nil?)
      raise ArgumentError, 'annotations file not found'
    end
    raise ArgumentError, "serviceaccount dir #{serviceaccount_dir} not found" if !Dir.exist?(serviceaccount_dir.to_s) && vault_auth_type == "kubernetes"
    raise ArgumentError, "api_url is null" if api_url.nil?

    @vault_mount = vault_mount
    @vault_prefix = vault_prefix
    @output_path = output_path
    @serviceaccount_dir = serviceaccount_dir
    @api_url = api_url
    @ssl_verify = ssl_verify
    @vault_v2 = vault_v2
    @pod_ip = find_pod_ip_v4 pod_ip
    @pod_hostname = pod_hostname || Socket.gethostname
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

    @secret_keys = if File.exist?(annotations.to_s)
      annotation_lines = File.read(annotations).split("\n")
      from_annotations(annotation_lines, /^secret\//)
    else
      from_env(/^#{env_secrets_prefix}/)
    end
    raise ArgumentError, "#{annotations} contains no secrets" if @secret_keys.empty?
    @logger.info(message: "secrets found", keys: @secret_keys)

    @pki_keys = if File.exist?(annotations.to_s)
      from_annotations(annotation_lines, /^pki\//)
    else
      from_env(/^#{env_pki_prefix}/)
    end
    @logger.info(message: "PKI found", keys: @pki_keys)
  end

  def write_secrets
    # TODO: remove
    File.write("#{@output_path}/LINK_LOCAL_IP", LINK_LOCAL_IP)

    # Write out the location of consul to simplify app logic
    # TODO: remove
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

    raise_errors errors

    # Write out user defined secrets
    secrets.each do |key, secret|
      File.write("#{@output_path}/#{key}", secret)
    end

    # notify primary container that it is now safe to read all secrets
    File.write("#{@output_path}/.done", Time.now.to_s)
  end

  def write_pki_certs
    return if @pki_keys.empty? # silence / do less work

    errors = []
    pkis = @pki_keys.map do |name, path|
      begin
        uri_path, data = split_url(path)

        # transform the data (request parameter) values:
        #  The VAULT API does not accept arrays
        #  1) empty arrays are dropped
        #  2) arrays are striped of empty entries and joined into a comma separated string
        data.delete_if { |_key, value| value.empty? }.
          transform_values! { |value| value.delete_if(&:empty?).join(',') }

        # translate 'reserved' parameters into real parameters in `data`
        if data.delete('pod_ip_as_san')&.downcase == 'true'
          data['ip_sans'] = [@pod_ip, *data['ip_sans']].join(',')
        end

        if data.delete('pod_hostname_as_cn')&.downcase == 'true'
          data['common_name'] = @pod_hostname
        end

        if data.delete('pod_hostname_as_san')&.downcase == 'true'
          data['alt_names'] = [@pod_hostname, *data['alt_names']].join(',')
        end

        [name, write_to_vault(uri_path, data)]
      rescue StandardError
        errors << $!
      end
    end

    raise_errors(errors)

    pkis.each do |name, data|
      cert_dir = "#{@output_path}/pki/#{name}"
      FileUtils.mkdir_p cert_dir

      File.write("#{cert_dir}/certificate.pem", data[:certificate])
      File.write("#{cert_dir}/expiration", data[:expiration])
      File.write("#{cert_dir}/issuing_ca.pem", data[:issuing_ca])
      File.write("#{cert_dir}/private_key.pem", data[:private_key])
      File.write("#{cert_dir}/private_key_type", data[:private_key_type])
      File.write("#{cert_dir}/serial_number", data[:serial_number])
      if data[:ca_chain]
        File.write("#{cert_dir}/ca_chain.pem", data[:ca_chain].join("\n"))
      end
    end
    @logger.info(message: "PKI certificates written")
  end

  private

  def raise_errors(errors)
    if errors.size == 1
      # regular error display with full backtrace
      raise errors.first
    elsif errors.size > 1
      # list all errors so users can fix multiple issues at once
      raise "Errors reading secrets:\n#{errors.map { |e| "#{e.class}: #{e.message}" }.join("\n")}"
    end
  end

  def serviceaccount_token
    @serviceaccount_token ||= File.read(@serviceaccount_dir + '/token')
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

  def write_to_vault(path, data)
    begin
      result = @vault.with_retries(Vault::HTTPConnectionError, Vault::PersistentHTTP::Error, attempts: 3) do
        @vault.logical.write(path, data)
      end
    rescue Vault::HTTPClientError
      $!.message.prepend "Error writing to #{path}\n"
      raise
    end

    if !result.respond_to?(:data) || !result.data.is_a?(Hash)
      raise "Bad results returned from vault server for #{path}: #{result.inspect}"
    end

    result.data
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

  def from_env(re_prefix)
    ENV.map do |key, path|
      next unless key =~ re_prefix
      [key.sub(re_prefix, ""), path]
    end.compact
  end

  # {re_prefix}/FOO="a/b/c/z" => {"FOO" => "a/b/c/z"}
  def from_annotations(annotations, re_prefix)
    annotations.map do |line|
      next unless line.sub! re_prefix, ""
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
      raise ArgumentError, "Unsupported Vault Auth Type: #{vault_auth_type}"
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

  # splits the given url; returning
  #  1) the URL path, and
  #  2) a hash containing the URL query parameters, when the
  #     URL contains no query paramets an empty hash is returned
  #
  # "pki/issue/cert?common_name=foo&ip_sans=127.0.0.1" ->
  #   [ "pki/issue/cert", { "common_name":["foo"], "ip_sans":["127.0.0.1"] } ]
  def split_url(path)
    uri = URI.parse(path)
    [uri.path, uri.query.nil? ? {} : CGI.parse(uri.query)]
  end

  # returns IPV4 dotted string
  def find_pod_ip_v4(pod_ip)
    pod_ip || Socket.ip_address_list.
      select { |addr| addr.ipv4? && !addr.ipv4_loopback? }.
      first.
      ip_address
  end
end
