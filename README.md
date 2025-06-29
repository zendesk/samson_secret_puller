# Secret puller [![CI](https://github.com/zendesk/samson_secret_puller/actions/workflows/actions.yml/badge.svg?branch=main)](https://github.com/zendesk/samson_secret_puller/actions/workflows/actions.yml)

Application to run in a kubernetes init container,
to publish secrets to containerized applications without using process environment
([which is unsafe](https://diogomonica.com/2017/03/27/why-you-shouldnt-use-env-variables-for-secret-data/)),
used in [samson](https://github.com/zendesk/samson),
and libraries for multiple languages to read these secrets from disk.

The init container understands these env vars:

```
VAULT_ADDR: required, url of vault
VAULT_AUTH_FILE: optional, location of the mounted vault token / pemfile on disk, defaults to '/vault-auth/authsecret'
VAULT_AUTH_TYPE: optional, the type of authentication to attempt, defaults to 'token'
VAULT_AUTH_PATH: optional, allows specifing a custom vault auth path, defaults to $VAULT_AUTH_TYPE
VAULT_AUTH_ROLE: optional, the role against which Vault login should be attempted (required where VAULT_AUTH_TYPE=kubernetes)
VAULT_TLS_VERIFY: optional, whether to verify ssl when talking to vault, defaults to false
VAULT_KV_V2: optional, wether this is vault kv v2, defaults to false
VAULT_MOUNT: optional, which mount to use, defaults to "secret"
VAULT_PREFIX: optional, which prefix to use, defaults to "apps"
SIDECAR_SECRET_PATH: optional, where to store the secrets on disk, defaults to  '/secrets'
SECRET_ANNOTATIONS: optional, where to read annotations from, defaults to '/secretkeys/annotations'
SERVICEACCOUNT_DIR: optional, where to service account from, defaults to '/var/run/secrets/kubernetes.io/serviceaccount/'
POD_IP: optional, the IP address assigned to the Kubernetes pod
POD_HOSTNAME: optional, the hostname assigned to the Kubernetes pod
LOG_LEVEL: optional, log level, defaults to "info"; set to "debug" when debugging
```

**(secrets in repo work only for testing)**.

Example config:

- [kubernetes/vault-auth-secret.yml](kubernetes/vault-auth-secret.yml)
- [kubernetes/vault-auth-token.yml](kubernetes/vault-auth-token.yml)

#### Supported Authentication Types

##### `VAULT_AUTH_TYPE=token` (default)

The file path specified in `VAULT_AUTH_FILE` will be read and used as a Vault token directly.
The token is validated using Vault's [lookup-self API](https://www.vaultproject.io/api/auth/token/index.html#lookup-a-token-self-).

##### `VAULT_AUTH_TYPE=cert`

The file path specified in `VAULT_AUTH_FILE` will be read and used as an X509 Certificate Vault
to authenticate with vault using the [TLS Certificate Auth backend](https://www.vaultproject.io/api/auth/cert/index.html).

If the backend is mounted at a different path from `/auth/cert`, it can be customised using the `VAULT_AUTH_PATH` env var.

##### `VAULT_AUTH_TYPE=kubernetes`

The Kubernetes ServiceAccount mounted into the init container will be used to
authenticate with vault using the [Kubernetes Auth backend](https://www.vaultproject.io/api/auth/kubernetes/index.html).
The role against which login will be attempted is set via `VAULT_AUTH_ROLE`.

If the backend is mounted at a different path from `/auth/kubernetes`, it can be customised using the `VAULT_AUTH_PATH` env var.

### Example workflow

Init container reads annotation `secret/BAR=foo/bar/baz/foo` and generates a file called `BAR` in `SIDECAR_SECRET_PATH`
with the content being the result of the vault read for `secret/apps/foo/bar/baz/foo`.
(`secret/apps` prefix is hardcoded atm)

Inside the host app, secrets are loaded by using the [samson_secret_puller](https://rubygems.org/gems/samson_secret_puller) gem.

```
gem 'samson_secret_puller'

require 'samson_secret_puller'

SamsonSecretPuller.replace_ENV!

ENV['FOO'] -> read from /secrets/FOO or falls back to ENV['FOO']
```

### Example PKI workflow

Init container reads annotations starting with `pki/`. PKI annotations are formatted as `pki/{name}={vault_path}?{parameters}`

The "name" in the annotation key is used in the path where the output files are written. The annotation's value
contains the vault URI path used to request certificate issuance. The URL-style path parameters in the annotation value
are converted into the payload of the generate certificate request.

For example: the init container reads the annotation `pki/example.com=pki/issue/example-com?common_name=example.com`
and generates certificate files in the path `${SIDECAR_SECRET_PATH}/pki/example.com` directory. The URL-style path parameters
in the annotation's value (`common_name=example.com`) will be marshalled into the payload of the
[Generate Certificate](https://www.vaultproject.io/api/secret/pki/index.html#generate-certificate) request to the
Vault instance (see that documentation for possible parameters).

Depending on how the PKI backend is configured the following files will be placed in the `SIDECAR_SECRET_PATH`
directory:

```
${SIDECAR_SECRET_PATH}/pki/example.com/certificate.pem
${SIDECAR_SECRET_PATH}/pki/example.com/private_key.pem
${SIDECAR_SECRET_PATH}/pki/example.com/issuing_ca.pem
${SIDECAR_SECRET_PATH}/pki/example.com/chain_ca.pem
${SIDECAR_SECRET_PATH}/pki/example.com/serial_number
${SIDECAR_SECRET_PATH}/pki/example.com/private_key_type
${SIDECAR_SECRET_PATH}/pki/example.com/expiration
```

**Special Annotation Parameters:**

- `?pod_hostname_as_cn=true`: Pod hostname is set to the common name, overriding the `common_name` parameter if provided
- `?pod_hostname_as_san=true`: Pod hostname is included as a subject alternate name
- `?pod_ip_as_san=true`: Pod IP is included as a subject alternate name

### Debugging

- Use a dedicated Pod to debug inside the cluster, see [kubernetes/debug.yml]
- There is no `bash`, use `sh`
- Set `LOG_LEVEL=debug` env var for debug logs

### Test

`bundle && bundle exec rake`

### Releasing a new gem version
A new version is published to RubyGems.org every time a change to `gem/lib/version.rb` is pushed to the `main` branch.
In short, follow these steps:
1. Update `version.rb`,
2. update version in the `Gemfile.lock` file,
3. merge this change into `main`, and
4. look at [the action](https://github.com/zendesk/samson_secret_puller/actions/workflows/publish.yml) for output.

To create a pre-release from a non-main branch:
1. change the version in `version.rb` to something like `1.2.0.pre.1` or `2.0.0.beta.2`,
2. push this change to your branch,
3. go to [Actions → “Publish to RubyGems.org” on GitHub](https://github.com/zendesk/samson_secret_puller/actions/workflows/publish.yml),
4. click the “Run workflow” button,
5. pick your branch from a dropdown.

### Release to [Docker Hub](https://hub.docker.com/r/zendesk/samson_secret_puller/)

- `docker pull zendesk/samson_secret_puller` gets the latest digest after merging a PR
- For branches, use `rake build` and then tag + push them manually
- For zendesk: [zendesk_samson_secret_puller](https://github.com/zendesk/zendesk_samson_secret_puller) pulls the latest and pushes a multi-arch image to GCR

## Ruby Gem

see [gem Readme.md](gem/Readme.md)

## Elixir

see [elixir README.md](elixir/README.md)
