# Secret puller [![Build Status](https://travis-ci.org/zendesk/samson_secret_puller.svg?branch=master)](https://travis-ci.org/zendesk/samson_secret_puller)

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
SIDECAR_SECRET_PATH: optional, where to store the secrets on disk, defaults to  '/secrets'
SECRET_ANNOTATIONS: optional, where to read annotations from, defaults to '/secretkeys/annotations'
SERVICEACCOUNT_DIR: optional, where to service account from, defaults to '/var/run/secrets/kubernetes.io/serviceaccount/'
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

### Debugging

Since the init-container always shuts down, debug by using a dedicated Pod, see [kubernetes/debug.yml]

### Test

`bundle && bundle exec rake`

### Release to [docker hub](https://hub.docker.com/r/zendesk/samson_secret_puller/)

Merge PR then `docker pull zendesk/samson_secret_puller` to get latest digest.
(for branches, `rake build` and then tag+push them manually)

## Ruby Gem

see [gem Readme.md](gem/Readme.md)

## Elixir

see [elixir README.md](elixir/README.md)
