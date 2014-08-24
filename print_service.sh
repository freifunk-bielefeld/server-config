#!/bin/sh

addr() {
	ip -$1 address show dev $2 2> /dev/null | tr '/' ' '| awk '/inet/{print($2); exit(0);}'
}

echo -n "{\"type\" : \"gateway\", \"addr\" : \"$(addr 4 bat0)\"}"
