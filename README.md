# Secret puller [![Build Status](https://travis-ci.org/zendesk/samson_secret_puller.svg?branch=master)](https://travis-ci.org/zendesk/samson_secret_puller)

Applciation to run in a kubernets sidecar app with used in [samson](https://github.com/zendesk/samson),
to publish secrets and configs to a containerized application.

Samon will need the following ENV vars set:

```
VAULT_ADDR: required
VAULT_AUTH_PEM: localtion of the mounted secret in the k8s cluster, defaults to '/vault-auth/pem'
VAULT_TLS_VERIFY: optional, defaults to, false
SIDECAR_SECRET_PATH: optional defaults to  '/secrets'
```

### Example

Sidecar reads annotations `secret/BAR=foo/bar/baz/foo` and generates a file called `BAR` in `SIDECAR_SECRET_PATH`
with the content being the result of the vault lookup for `foo/bar/baz/foo`.

### Test

`bundle && rake`

### Build

```
... build ...
docker build -t samson-secret-puller .
docker tag -f samson-secret-puller docker-registry.zende.sk/samson-secret-puller:latest
docker push docker-registry.zende.sk/samson-secret-puller:latest
```
