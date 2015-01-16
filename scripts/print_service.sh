#!/bin/sh

addr() {
	ip -$1 address show dev $2 2> /dev/null | tr '/' ' '| awk '/inet/{if($2 ~ /^fdef/) { print($2); exit(0);} }'
}

echo -n "{\"link\" : \"http://[$(addr 6 bat0)]/index.html\", \"label\" : \"Freifunk Gateway $(hostname -s)\"}"
