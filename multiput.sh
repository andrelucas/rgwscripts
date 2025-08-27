#!/bin/bash

count=2
if [ -n "$1" ]; then
	count=$1
fi

cmd="s3cmd put /etc/hosts s3://testnv/hosts"

echo -n "Launch: "
for n in $(seq 1 $count); do
	echo -n "$n "
	$cmd &
done
echo

wait
