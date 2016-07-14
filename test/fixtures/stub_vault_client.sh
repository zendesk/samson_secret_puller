#!/usr/bin/env bash

##
# this is a little stub of the vault client
# to get around a bunch of issues in testing
# mostly to do with ssl
##



function auth() {
  curl  -s http://localhost:$VAULT_PORT/auth 
  if [ $? -ne 0 ]; then
    echo "fail"
    exit -1
  fi
}

function token_create() {
  curl  -s http://localhost:$VAULT_PORT/auth/token/create
  if [ $? -ne 0 ]; then
    echo "fail"
    exit -1
  fi
}

case $1 in
  auth) auth;;
  token-create) token_create;;
esac
