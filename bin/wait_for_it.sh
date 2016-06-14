#!/bin/bash

# little script that simply watches for the secret puller to be done.  
# script will return 0 on success, 1 on timeout (we'll give the puller 60s), and 2 for any other error

if [ -z ${DONE_FILE} ]; then
  DONE_FILE=/secrets/.done
fi

if [ -z $1 ]; then
  TIMEOUT=60
  else
  TIMEOUT=$1
fi

function exit_success {
  exit 0
}

function exit_timeout {
  echo "Timeout waiting for secrets"
  exit 1
}

function exit_error {
  exit 2
}

while [ $TIMEOUT -gt 0 ]; do
  TIMEOUT=$(($TIMEOUT - 1))
  if [ -f $DONE_FILE ]; then
    exit_success
  fi
  sleep 1
done

exit_timeout
