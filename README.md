# Secret puller [![Build Status](https://travis-ci.org/zendesk/samson_secret_puller.svg?branch=master)](https://travis-ci.org/zendesk/samson_secret_puller)

Application to run in a kubernetes sidecar app with used in [samson](https://github.com/zendesk/samson),
to publish secrets and configs to a containerized application.

Samson will need the following ENV vars set:

```
VAULT_ADDR: required
VAULT_AUTH_FILE: localtion of the mounted secret in the k8s cluster, defaults to '/vault-auth/authsecret'
VAULT_TLS_VERIFY: optional, defaults to, false
SIDECAR_SECRET_PATH: optional defaults to  '/secrets'
```
Your kubernetes cluster will also requires a few objects in order for this
to work.  A token or an pemfile (VAULT_AUTH_FILE) will need to be created
in vault, then the secret object will need to be created.  The contents
of the secret must be base64 encoded, and cannot include EOF.  See:
kubernets/vault-auth-secret.yml
kubernets/vault-auth-token.yml

### Example

Sidecar reads annotations `secret/BAR=foo/bar/baz/foo` and generates a file called `BAR` in `SIDECAR_SECRET_PATH`
with the content being the result of the vault lookup for `foo/bar/baz/foo`.

Inside the host app secrets are loaded by using the `samson_secret_puller` gem.

```
gem 'samson_secret_puller'

require 'samson_secret_puller'

SamsonSecretPuller.replace_ENV! # waits for /secret/.done to show up

ENV['FOO'] -> read from /secrets/FOO or falls back to ENV['FOO']
```

### Test

`bundle && rake`

### Build

```
... build ...
docker build -t samson-secret-puller .
docker tag -f samson-secret-puller docker-registry.zende.sk/samson-secret-puller:latest
docker push docker-registry.zende.sk/samson-secret-puller:latest
```


### Gem

```
cd gem
rake bump:patch
rake release
```
