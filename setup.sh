#!/bin/sh

#A server setup script (alpha)

#abort script on first error
set -e

is_running() {
  ps aux | grep -v grep | grep "$1" &> /dev/null
}

is_installed() {
	which "$1" &> /dev/null
}

get_mac() {
	local mac=`cat /sys/class/net/$1/address`

	# translate to local administered mac
	a=${mac%%:*} #cut out first hex
	a=$((0x$a ^ 2)) #invert second least significant bit
	a=`printf '%02x\n' $a` #convert back to hex
	echo "$a:${mac#*:}" #reassemble mac
}

get_ula() {
	local prefix="$1" mac="$2"

	mac=${mac//:/} # remove ':'
	mac=${mac:0:6}fffe${mac:6:6} # insert ffee
	mac=`echo $mac | sed 's/..../&:/g'` # insert ':'

	# assemble IPv6 address
	echo "${prefix%%::*}:${mac%?}"
}

if ! is_installed "alfred"; then
	echo "(I) Install batman, batctl and alfred."
	VERSION=2014.3.0
	apt-get install build-essential 
	apt-get install linux-headers-$(uname -r)
	apt-get install pkg-config
	apt-get install libnl-3-dev

	wget http://downloads.open-mesh.org/batman/releases/batman-adv-$VERSION/batman-adv-$VERSION.tar.gz
	tar -xzf batman-adv-$VERSION.tar.gz
	cd batman-adv-$VERSION/
	make
	make install
	cd ..
	rm -rf batman-adv-$VERSION*

	wget http://downloads.open-mesh.org/batman/releases/batctl-$VERSION/batctl-$VERSION.tar.gz
	tar -xzf batctl-$VERSION.tar.gz
	cd batctl-$VERSION/
	make
	make install
	cd ..
	rm -rf batctl-$VERSION*

	wget http://downloads.open-mesh.org/batman/stable/sources/alfred/alfred-$VERSION.tar.gz
	tar -xzf alfred-$VERSION.tar.gz
	cd alfred-$VERSION/
	make CONFIG_ALFRED_GPSD=n 
	make CONFIG_ALFRED_GPSD=n install
	cd ..
	rm -rf alfred-$VERSION*
fi

if ! is_installed "radvd"; then
	echo "(I) Install radvd."
	apt-get install radvd
fi

if ! is_installed "tayga"; then
	echo "(I) Install tayga."
	apt-get install tayga
fi

if ! is_installed "fastd"; then
	echo "(I) Install fastd."
	apt-get install git cmake-curses-gui libnacl-dev flex bison libcap-dev pkg-config zip

	git clone http://git.universe-factory.net/fastd 
	git clone http://git.universe-factory.net/libuecc

	mkdir fastd_build
	mkdir libuecc_build

	cd libuecc_build
	cmake ../libuecc
	make 
	make install
	cd ..
	rm -rf libuecc_build libuecc

	cd fastd_build
	cmake ../fastd
	make
	make install
	cd ..
	rm -rf fastd_build fastd
fi

if ! is_installed "openvpn"; then
	echo "(I) Install openvpn."
	apt-get install openvpn
fi

if ! lsmod | grep -v grep | grep "batman_adv" > /dev/null; then
  echo "(I) Start batman-adv."
  echo "5000" >  /sys/class/net/bat0/mesh/orig_interval
fi

if ! is_running "alfred"; then
  echo "(I) Start alfred."
  alfred -i bat0  -b bat0 -m &> /dev/null &
fi

if ! id nobody 2> /dev/null; then
	echo "(I) Create user nobody for fastd."
	useradd --system --no-create-home --shell /bin/false nobody
fi

if ! is_running "fastd"; then
  echo "(I) Start fastd."
  fastd --config /etc/fastd/vpn/fastd.conf --daemon
fi

if ! is_running "radvd"; then
  echo "(I) Start radvd."
  /etc/init.d/radvd start
fi

if ! is_running "tayga"; then
  echo "(I) Start tayga."
  /etc/init.d/tayga start
fi

#we like to have a constant MAC
#to be able to track a node on the map.
mac="get_mac eth0"

ip addr flush dev fastd_mesh
ip link set fastd_mesh up

ip link set bat0 down
ip link set bat0 address "$mac"
batctl if add fastd_mesh
ip link set bat0 up

ip -6 addr add "get_ula fdef:17a0:ffb1:300::/64 $mac" dev bat0
ip -6 addr add "get_ula 2001:bf7:1320:300::/64 $mac" dev bat0
