#!/usr/bin/env bash

##
# little stubb'd k8s client for testing purposes
##

curl -s http://localhost:8443/api/v1/namespaces/default/secrets/vaultauth

