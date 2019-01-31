# Secret puller [![Build Status](https://travis-ci.org/zendesk/samson_secret_puller.svg?branch=master)](https://travis-ci.org/zendesk/samson_secret_puller)

Application to run in a kubernetes init container,
to publish secrets to containerized applications without using process environment 
([which is unsafe](https://diogomonica.com/2017/03/27/why-you-shouldnt-use-env-variables-for-secret-data/)),
used in [samson](https://github.com/zendesk/samson),

and libraries for multiple languages to read these secrets from disk.

The init container understands these env vars:

```
VAULT_ADDR: required, url of vault
VAULT_AUTH_FILE: required. path to token or pemfile on disk

VAULT_AUTH_FILE: optional, location of the mounted secret on disk, defaults to '/vault-auth/authsecret'
VAULT_TLS_VERIFY: optional, wether to verify ssl when talking to vault, defaults to false
VAULT_KV_V2: optional, wether this is vault kv v2, defaults to false
SIDECAR_SECRET_PATH: optional, where to store the secrets on disk, defaults to  '/secrets'
SECRET_ANNOTATIONS: optional, where to read annotations from, defaults to '/secretkeys/annotations'
SERVICEACCOUNT_DIR: optional, where to service account from, defaults to '/var/run/secrets/kubernetes.io/serviceaccount/'
```

**(secrets in repo work only for testing)**.    

Example config:
 - [kubernetes/vault-auth-secret.yml](kubernetes/vault-auth-secret.yml)
 - [kubernetes/vault-auth-token.yml](kubernetes/vault-auth-token.yml)

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

### Debugging

Since the init-container always shuts down, debug by using a dedicated Pod, see [kubernetes/debug.yml]

### Test

`bundle && bundle exec rake`

### Release to [docker hub](https://hub.docker.com/r/zendesk/samson_secret_puller/)

```
bundle exec rake release
```

## Ruby Gem

see [gem Readme.md](gem/Readme.md)

## Elixir

see [elixir README.md](elixir/README.md)
