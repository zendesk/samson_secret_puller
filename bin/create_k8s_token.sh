#!/usr/bin/env bash

##
# little script that will create a vault token for the secret puller, and then store it as a 
# k8s secret object that the secret puller will use.
# 
# requires that the vault cli and the kubectl command are available.  
# also requires a cert to talk to valut.  this cert *MUST* be associcated
# with policies that have enough permissions to create new tokens
##

DEBUG_MODE="false"
SECERT_PULLER_TOKEN="false"
NEW_TOKEN="false"

while getopts ":hdv:t:k:" opt; do
  case $opt in
    h) usage ;;
    v) VAULT_ADDR=$OPTARG;;
    t) VAULT_TOKEN=$OPTARG;;
    k) KUBE_CONFIG=$OPTARG;;
    d) DEBUG_MODE="true";;
  esac
done

function exit_success() {
  echo $1
  exit 0
}

function exit_failure() {
  echo $1
  exit -1
}

function usage() {
  exit_failure "usage: $0 -v vault_addr -t vault_token -k path_to_kubeconfig"
}

function vault_auth() {
  NEW_TOKEN=$($VAULT_CLI auth $VAULT_TOKEN | grep token | head -1 | awk '{print $2}')  2> /dev/null
  if [ $? -ne 0 ]; then
    exit_failure "could not auth with vault"
  fi
}

function generate_vault_token() {
# TODO: get a policy set up for secretpuller
SECRET_PULLER_TOKEN=$($VAULT_CLI token-create -display-name="samson" -ttl="24h" -policy="samson")
  if [ $? -ne 0 ]; then
    exit_failure "could not get token for secret puller"
  fi
}

function store_k8s_token() {
  cat <<EOF | $KUBECTL replace -f 1>&2 > /dev/null -
apiVersion: v1
kind: Secret
metadata:
  name: vaultauth
type: Opaque
data:
  authsecret: $(echo $(echo $SECRET_PULLER_TOKEN | $BASE64))
EOF

  if [ $? -ne 0 ]; then
    exit_failure "could create secret in k8s"
  fi
}

function verify_options() {
  # stub the vault client here to make sure that testing works
  if [ -n $CRON_TEST ] ; then
    VAULT_CLI=$BUNDLER_ROOT/test/fixtures/stub_vault_client.sh
  else
    VAULT_CLI=$(which vault)
    if [ ! -x $VAULT_CLI ] ; then
      exit_failure "cannot find valult cli"
    fi
  fi
  # stub the k8s client here to make sure that testing works
  if [ -n $CRON_TEST ] ; then
    KUBECTL=$BUNDLER_ROOT/test/fixtures/stub_kubectl.sh
  else
    KUBECTL=$(which kubectl)
    if [ ! -x $KUBECTL ] ; then
      exit_failure "cannot find kybectl"
    fi
  fi
  BASE64=$(which base64)
  if [ ! -x $BASE64 ] ; then
    exit_failure "cannot find base64"
  fi
  if [ -z $VAULT_ADDR ] ; then
    echo "-v VAULT_ADDR missing"
    usage
  fi
  if [ -z $VAULT_TOKEN ] ; then
    echo "-t VAULT_TOKEN missing"
    usage
  fi
  if [ -z $KUBE_CONFIG ] ; then
    echo "-k KUBE_CONFIG missing"
    usage
  fi
}

function main() {
  verify_options
  if [ $DEBUG_MODE == "true" ]; then
    echo "==== DEBUG ===="
    echo "VAULT_ADDR = $VAULT_ADDR"
    echo "VAULT_TOKEN = $VAULT_TOKEN"
    echo "KUBE_CONFIG = $KUBE_CONFIG"
  fi

  vault_auth
  generate_vault_token
  store_k8s_token
  exit_success "token generated"
}

# run the script
main
