#!/bin/sh

#This script is called every 5 minutes via crond

#Server address
mac_addr=""
ip_addr=""
ff_prefix=""

#For the map
geo=""
name="$(hostname)"
firmware="server"
community="bielefeld"
vpn="true"
gateway="false"

#start/stop OpenVPN, bind, tayga, radvd
handle_gateway_tools="true"

##############

#abort script on first error
set -e
set -u

export PATH=$PATH:/usr/local/sbin:/usr/local/bin

#switch script directory
cd "$(dirname $0)"

[ -n "$ff_prefix" ] || { echo "(E) ff_prefix not set!"; exit 1; }
[ -n "$ip_addr" ] || { echo "(E) ip_addr not set!"; exit 1; }
[ -n "$mac_addr" ] || { echo "(E) mac_addr not set!"; exit 1; }

is_running() {
	pidof "$1" > /dev/null || return $?
}

addr() {
	ip -$1 address show dev $2 2> /dev/null | tr '/' ' '| awk '/inet/{if($2 ~ /^fdef/) { print($2); exit(0);} }'
}

#make sure batman-adv is loaded
modprobe batman_adv

if ! is_running "fastd"; then
	echo "(I) Start fastd."
	fastd --config /etc/fastd/fastd.conf --daemon
	sleep 1
fi

if [ ! -d /sys/class/net/fastd_mesh/batman_adv/ ]; then
	echo "(I) Add fastd interface to batman-adv."
	ip link set fastd_mesh up
	ip addr flush dev fastd_mesh
	batctl if add fastd_mesh
fi

if [ "$(cat /sys/class/net/bat0/address 2> /dev/null)" != "$mac_addr" ]; then
	echo "(I) Set MAC address for bat0."
	ip link set bat0 down
	ip link set bat0 address "$mac_addr"
	ip link set bat0 up

	echo "(I) Configure batman-adv."
	echo "5000" >  /sys/class/net/bat0/mesh/orig_interval
	echo "0" >  /sys/class/net/bat0/mesh/distributed_arp_table
	echo "0" >  /sys/class/net/bat0/mesh/multicast_mode
fi

if [ "$(ip -6 addr list dev bat0 | grep -c $ip_addr)" = "0" ]; then
	echo "(I) Set IP-Address of bat0 to $ip_addr"
	ip -6 addr add "$ip_addr/64" dev bat0
fi

if ! is_running "alfred"; then
	echo "(I) Start alfred."
	start-stop-daemon --start --background --exec `which alfred` -- -i bat0 -m
fi

if ! is_running "lighttpd"; then
	echo "(I) Start lighttpd."
	/etc/init.d/lighttpd start
fi

if [ "$handle_gateway_tools" = "true" ]; then
	if [ "$gateway" = "true" ]; then
		if ! is_running "openvpn"; then
			echo "(I) Start openvpn."
			/etc/init.d/openvpn start
		fi

		if ! is_running "tayga"; then
			echo "(I) Start tayga."
			tayga
		fi

		if ! is_running "named"; then
			echo "(I) Start bind."
			/etc/init.d/bind9 start
		fi

		if ! is_running "radvd"; then
			echo "(I) Start radvd."
			/etc/init.d/radvd start
		fi
	else
		if is_running "openvpn"; then
			echo "(I) Stop openvpn."
			/etc/init.d/openvpn stop
		fi

		if is_running "tayga"; then
			echo "(I) Stop tayga."
			killall tayga
		fi

		if is_running "named"; then
			echo "(I) Stop bind."
			/etc/init.d/bind9 stop
		fi

		if is_running "radvd"; then
			echo "(I) Stop radvd."
			/etc/init.d/radvd stop
		fi
	fi
fi

#announce status website via alfred
{
	echo -n "{\"link\" : \"http://[$(addr 6 bat0)]/index.html\", \"label\" : \"Freifunk Gateway $(hostname -s)\"}"
} | alfred -s 91


#announce map information via alfred
{
	echo -n "{"

	[ -n "$geo" ] && echo -n "\"geo\" : \"$geo\", "
	[ -n "$name" ] && echo -n "\"name\" : \"$name\", "
	[ -n "$firmware" ] && echo -n "\"firmware\" : \"$firmware\", "
	[ -n "$community" ] && echo -n "\"community\" : \"$community\", "
	[ -n "$vpn" ] && echo -n "\"vpn\" : $vpn, "
	[ -n "$gateway" ] && echo -n "\"gateway\" : $gateway, "
	[ -n "$vpn" ] && echo -n "\"vpn\" : $vpn, "

	echo -n "\"links\" : ["

	printLink() { echo -n "{ \"smac\" : \"$(cat /sys/class/net/$3/address)\", \"dmac\" : \"$1\", \"qual\" : $2 }"; }
	IFS="
	"
	nd=0
	for entry in $(cat /sys/kernel/debug/batman_adv/bat0/originators |  tr '\t/[]()' ' ' |  awk '{ if($1==$4) print($1, $3, $5) }'); do
		[ $nd -eq 0 ] && nd=1 || echo -n ", "
		IFS=" "
		printLink $entry
	done

	echo -n '], '
	echo -n "\"clientcount\" : 0"
	echo -n '}'
} | gzip -c - | alfred -s 64


#collect all map pieces
alfred -r 64 > /tmp/maps.txt

#create map data
./ffmap-backend.py -m /tmp/maps.txt -a ./aliases.json > /var/www/map/nodes.json

#update FF-Internal status page
./status_page_create.sh '/var/www/index.html'

#update nodes/clients/gateways counter
./counter_update.py '/var/www/map/nodes.json' '/var/www/counter/counter.svg'

echo "done"
