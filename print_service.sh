#!/bin/sh

addr() {
	ip -$1 address show dev $2 2> /dev/null | tr '/' ' '| awk '/inet/{print($2); exit(0);}'
}

echo -n "{\"link\" : \"$(addr 4 bat0)\", \"label\" : \"Freifunk Gateway VPN1\"}"
