#!/bin/bash

#This script sets up a Freifunk server consisting
#of batman-adv, fastd and a web server for the status site.

#Secret key for fastd (optional).
fastd_secret=""

#The servers Internet interface.
wan_iface="eth0"

#The community identifier.
community_id="bielefeld"

#The internal IPv6 prefix
ff_prefix="fdef:17a0:ffb1:300::"

#Set to 1 for this script to run. :-)
run=0

export PATH=$PATH:/usr/local/sbin:/usr/local/bin

#####################################

#abort script on first error
set -e
set -u

if [ $run -eq 0 ]; then
	echo "Check the variables in this script and then set run to 1!"
	exit 1
fi

is_running() {
  pidof "$1" > /dev/null || return $?
}

is_installed() {
  which "$1" > /dev/null || return $?
}

sha256check() {
	local file="$1" hash="$2"
	if [ "$(sha256sum $file | cut -b 1-64)" != "$hash" ]; then
		echo "(E) Hash mismatch: $file"
		exit 1
	fi
}

ula_addr() {
	local prefix="$1"
	local mac="$2"

	# translate to local administered mac
	a=${mac%%:*} #cut out first hex
	a=$((0x$a ^ 2)) #invert second least significant bit
	a=`printf '%02x\n' $a` #convert back to hex
	mac="$a:${mac#*:}" #reassemble mac

	mac=${mac//:/} # remove ':'
	mac=${mac:0:6}fffe${mac:6:6} # insert ffee
	mac=`echo $mac | sed 's/..../&:/g'` # insert ':'

	# assemble IPv6 address
	echo "${prefix%%::*}:${mac%?}"
}

get_mac() {
	local mac=`cat /sys/class/net/$1/address`

	# translate to local administered mac
	a=${mac%%:*} #cut out first hex
	a=$((0x$a ^ 2)) #invert second least significant bit
	a=`printf '%02x\n' $a` #convert back to hex
	echo "$a:${mac#*:}" #reassemble mac
}

mac="$(get_mac $wan_iface)"
addr="$(ula_addr $ff_prefix $mac)"

echo "(I) This server will have the internal IP address: $addr"


if [ ! -f /root/scripts/update.sh ]; then
	echo "(I) Create /root/scripts/"
	apt-get install --assume-yes python3 python3-jsonschema
	cp -rf scripts /root/

	if [ -n "$community_id" ]; then
		sed -i "s/community=\"\"/community=\"$community_id\"/g" /root/scripts/print_map.sh
	fi
fi

if [ ! -d /etc/iptables ]; then
	echo "(I) Installing persistent iptables"
	apt-get install --assume-yes netfilter-persistent
	cp -rf etc/iptables /etc/

	/etc/init.d/netfilter-persistent restart
fi

if ! is_installed "lighttpd"; then
	echo "(I) Install lighttpd"
	apt-get install --assume-yes lighttpd
fi

if [ ! -f /etc/lighttpd/lighttpd.conf ]; then
	echo "(I) Create /etc/lighttpd/lighttpd.conf"
	cp etc/lighttpd/lighttpd.conf /etc/lighttpd/
	sed -i "s/fdef:17a0:ffb1:300::1/$addr/g" /etc/lighttpd/lighttpd.conf
fi

if ! id www-data >/dev/null 2>&1; then
	echo "(I) Create user/group www-data for lighttpd."
	useradd --system --no-create-home --user-group --shell /bin/false www-data
fi

if [ ! -d /var/www/status ]; then
	echo "(I) Create /var/www/status"
	mkdir -p /var/www/status
	cp -r var/www/status /var/www/

	chown -R www-data:www-data var/www
fi

if [ ! -d /var/www/map ]; then
	echo "(I) Create /var/www/map"
	apt-get install --assume-yes make
	git clone https://github.com/freifunk-bielefeld/ffmap-d3.git
	cd ffmap-d3
	make
	mkdir -p /var/www/map
	cp -r www/* /var/www/map/
	cd ..
	rm -rf ffmap-d3
	chown -R www-data:www-data /var/www
fi

if [ ! -d /var/www/counter ]; then
	echo "(I) Create /var/www/counter"
	mkdir -p /var/www/counter
	cp -r var/www/counter /var/www/
	chown -R www-data:www-data var/www
fi

if [ -z "$(cat /etc/crontab | grep '/root/scripts/update.sh')" ]; then
	echo "(I) Add entry to /etc/crontab"
	echo '*/5 * * * * root /root/scripts/update.sh' >> /etc/crontab
fi

if ! is_installed "alfred"; then
	VERSION=2014.4.0

	echo "(I) Install batman-adv, batctl and alfred ($VERSION)."
	apt-get install --assume-yes wget build-essential linux-headers-$(uname -r) pkg-config libnl-3-dev libjson-c-dev

	#install batman-adv
	wget --no-check-certificate http://downloads.open-mesh.org/batman/releases/batman-adv-$VERSION/batman-adv-$VERSION.tar.gz
	sha256check "batman-adv-$VERSION.tar.gz" "757b9ddd346680f6fd87dc28fde6da0ddc0423a65fbc88fdbaa7b247fed2c1a8"
	tar -xzf batman-adv-$VERSION.tar.gz
	cd batman-adv-$VERSION/
	make
	make install
	cd ..
	rm -rf batman-adv-$VERSION*

	#install batctl
	wget --no-check-certificate http://downloads.open-mesh.org/batman/releases/batman-adv-$VERSION/batctl-$VERSION.tar.gz
	sha256check "batctl-$VERSION.tar.gz" "77509ed70232ebc0b73e2fa9471ae13b12d6547d167dda0a82f7a7fad7252c36"
	tar -xzf batctl-$VERSION.tar.gz
	cd batctl-$VERSION/
	make
	make install
	cd ..
	rm -rf batctl-$VERSION*

	#install alfred
	wget --no-check-certificate http://downloads.open-mesh.org/batman/stable/sources/alfred/alfred-$VERSION.tar.gz
	sha256check "alfred-$VERSION.tar.gz" "99e6c64e7069b0b7cb861369d5c198bfc7d74d41509b8edd8a17ba78e7c8d034"
	tar -xzf alfred-$VERSION.tar.gz
	cd alfred-$VERSION/
	make CONFIG_ALFRED_GPSD=n 
	make CONFIG_ALFRED_GPSD=n install
	cd ..
	rm -rf alfred-$VERSION*
fi

if ! is_installed "fastd"; then
	echo "(I) Install fastd."

	apt-get install --assume-yes git cmake-curses-gui libnacl-dev flex bison libcap-dev pkg-config zip libjson-c-dev

	#install libsodium
	wget --no-check-certificate http://github.com/jedisct1/libsodium/releases/download/1.0.0/libsodium-1.0.0.tar.gz
	sha256check "libsodium-1.0.0.tar.gz" "ced1fe3d2066953fea94f307a92f8ae41bf0643739a44309cbe43aa881dbc9a5"
	tar -xvzf libsodium-1.0.0.tar.gz
	cd libsodium-1.0.0
	./configure
	make
	make install
	cd ..
	rm -rf libsodium-1.0.0*
	ldconfig

	#install libuecc
	wget --no-check-certificate https://projects.universe-factory.net/attachments/download/80 -O libuecc-5.tar.xz
	sha256check "libuecc-5.tar.xz" "a9a4bc485019410a0fbd484c70a5f727bb924b7a4fe24e6224e8ec1e9a9037e7"
	tar xf libuecc-5.tar.xz
	mkdir libuecc_build
	cd libuecc_build
	cmake ../libuecc-5
	make
	make install
	cd ..
	rm -rf libuecc_build libuecc-5*
	ldconfig

	#install fastd
	wget --no-check-certificate https://projects.universe-factory.net/attachments/download/81 -O fastd-17.tar.xz
	sha256check "fastd-17.tar.xz" "26d4a8bf2f8cc52872f836f6dba55f3b759f8c723699b4e4decaa9340d3e5a2d"
	tar xf fastd-17.tar.xz
	mkdir fastd_build
	cd fastd_build
	cmake ../fastd-17
	make
	make install
	cd ..
	rm -rf fastd_build fastd-17*
fi

if [ ! -f /etc/fastd/fastd.conf ]; then
	echo "(I) Configure fastd"
	cp -r etc/fastd /etc/

	if [ -z "$fastd_secret" ]; then
		echo "(I) Create Fastd private key pair. This may take a while..."
		fastd_secret=$(fastd --generate-key --machine-readable)
	fi
	echo "secret \"$fastd_secret\";" >> /etc/fastd/fastd.conf
	fastd_key=$(echo "secret \"$fastd_secret\";" | fastd --config - --show-key --machine-readable)
	echo "#key \"$fastd_key\";" >> /etc/fastd/fastd.conf
fi

if ! id nobody >/dev/null 2>&1; then
	echo "(I) Create user nobody for fastd."
	useradd --system --no-create-home --shell /bin/false nobody
fi

if ! lsmod | grep -v grep | grep "batman_adv" > /dev/null; then
  echo "(I) Start batman-adv."
  modprobe batman_adv
fi

if ! is_running "fastd"; then
  echo "(I) Start fastd."
  fastd --config /etc/fastd/fastd.conf --daemon
  sleep 1
fi

echo "(I) Add fastd interface to batman-adv."
ip link set fastd_mesh up
ip addr flush dev fastd_mesh
batctl if add fastd_mesh

echo "(I) Set MAC address for bat0."
ip link set bat0 down
ip link set bat0 address "$mac"
ip link set bat0 up

echo "(I) Configure batman-adv."
echo "5000" >  /sys/class/net/bat0/mesh/orig_interval
echo "1" >  /sys/class/net/bat0/mesh/distributed_arp_table
echo "0" >  /sys/class/net/bat0/mesh/multicast_mode

ip -6 addr add $addr/64 dev bat0

if ! is_running "alfred"; then
  echo "(I) Start alfred."
  start-stop-daemon --start --background --exec `which alfred` -- -i bat0 -m
fi

if ! is_running "lighttpd"; then
  echo "(I) Start lighttpd."
  /etc/init.d/lighttpd start
fi
