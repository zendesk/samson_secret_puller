#!/bin/sh

# little script that simply watches for the secret puller to be done.  
# script will return 0 on success, 1 on timeout (we'll give the puller 60s), and 2 for any other error

DONE_FILE=/secrets/.done
TIME=60

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

while [ $TIME -gt 0 ]; do
	TIME=$(($TIME - 1))
	sleep 1
	if [ -f /tmp/.done ]; then
		exit_success
	fi
done

exit_timeout
