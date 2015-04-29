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

#setup a gateway with http://mullvad.net
setup_gateway="false"

#Set to 1 for this script to run. :-)
run=0

#####################################

export PATH=$PATH:/usr/local/sbin:/usr/local/bin

#abort script on first error
set -e
set -u

if [ $run -eq 0 ]; then
	echo "Check the variables in this script and then set run to 1!"
	exit 1
fi

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
	local prefix="$1" mac="$2" a

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
	local mac="$(cat /sys/class/net/$1/address)" a

	# translate to local administered mac
	a=${mac%%:*} #cut out first hex
	a=$((0x$a ^ 2)) #invert second least significant bit
	a=`printf '%02x\n' $a` #convert back to hex
	echo "$a:${mac#*:}" #reassemble mac
}

if ! ip addr list dev $wan_iface &> /dev/null; then
	echo "(E) Interface $wan_iface does not exist."
	exit
fi

mac_addr="$(get_mac $wan_iface)"
ip_addr="$(ula_addr $ff_prefix $mac_addr)"

if [ -z "$mac_addr" -o -z "$ip_addr" ]; then
	echo "(E) MAC or IP address no set."
	exit
fi

echo "(I) Update package database"
apt-get update

{
	echo "(I) Create /root/scripts/"
	apt-get install --assume-yes python3 python3-jsonschema
	cp -rf scripts /root/

	sed -i "s/ip_addr=\".*\"/ip_addr=\"$ip_addr\"/g" /root/scripts/update.sh
	sed -i "s/mac_addr=\".*\"/mac_addr=\"$mac_addr\"/g" /root/scripts/update.sh
	sed -i "s/community=\".*\"/community=\"$community_id\"/g" /root/scripts/update.sh
	sed -i "s/ff_prefix=\".*\"/ff_prefix=\"$ff_prefix\"/g" /root/scripts/update.sh
}

{
	echo "(I) Install lighttpd"
	apt-get install --assume-yes lighttpd
}

{
	echo "(I) Create /etc/lighttpd/lighttpd.conf"
	cp etc/lighttpd/lighttpd.conf /etc/lighttpd/
	sed -i "s/fdef:17a0:ffb1:300::1/$ip_addr/g" /etc/lighttpd/lighttpd.conf
}

if ! id www-data >/dev/null 2>&1; then
	echo "(I) Create user/group www-data for lighttpd."
	useradd --system --no-create-home --user-group --shell /bin/false www-data
fi

{
	echo "(I) Populate /var/www"
	mkdir -p /var/www/
	cp -r var/www/* /var/www/

	echo "(I) Add ffmap-d3"
	apt-get install --assume-yes make git
	git clone https://github.com/freifunk-bielefeld/ffmap-d3.git
	cd ffmap-d3
	make
	cp -r www/* /var/www/
	cd ..
	rm -rf ffmap-d3

	chown -R www-data:www-data /var/www
}

if [ -z "$(cat /etc/crontab | grep '/root/scripts/update.sh')" ]; then
	echo "(I) Add entry to /etc/crontab"
	echo '*/5 * * * * root /root/scripts/update.sh > /dev/null' >> /etc/crontab
fi

if ! is_installed "alfred"; then
	VERSION=2014.4.0

	echo "(I) Install batman-adv, batctl and alfred ($VERSION)."
	apt-get install --assume-yes wget build-essential linux-headers-$(uname -r) pkg-config libnl-3-dev libjson-c-dev git

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

{
	echo "(I) Configure fastd"
	cp -r etc/fastd /etc/

	if [ -z "$fastd_secret" ]; then
		echo "(I) Create Fastd private key pair. This may take a while..."
		fastd_secret=$(fastd --generate-key --machine-readable)
	fi
	echo "secret \"$fastd_secret\";" >> /etc/fastd/fastd.conf
	fastd_key=$(echo "secret \"$fastd_secret\";" | fastd --config - --show-key --machine-readable)
	echo "#key \"$fastd_key\";" >> /etc/fastd/fastd.conf

	sed -i "s/eth0/$wan_iface/g" /etc/fastd/fastd.conf
}

if ! id nobody >/dev/null 2>&1; then
	echo "(I) Create user nobody for fastd."
	useradd --system --no-create-home --shell /bin/false nobody
fi

### setup gateway ###

if [ "$setup_gateway" = "true" ]; then

	{
		if ! ip6tables -t nat -L > /dev/null  2>&1; then
			echo "(E) NAT66 support not available in Linux kernel."
			exit 1
		fi

		echo "(I) Installing persistent iptables"
		apt-get install --assume-yes iptables-persistent

		cp -rf etc/iptables/* /etc/iptables/
		/etc/init.d/iptables-persistent restart
	}

	setup_mullvad() {
		local mullvad_zip="$1"
		local tmp_dir="/tmp/mullvadconfig"

		if [ ! -f "$mullvad_zip" ]; then
			echo "Mullvad zip file missing: $mullvad_zip"
			exit 1
		fi

		#unzip and copy files to OpenVPN
		rm -rf $tmp_dir
		mkdir -p $tmp_dir
		unzip $mullvad_zip -d $tmp_dir
		cp $tmp_dir/*/mullvad_linux.conf /etc/openvpn
		cp $tmp_dir/*/mullvad.key /etc/openvpn
		cp $tmp_dir/*/mullvad.crt /etc/openvpn
		cp $tmp_dir/*/ca.crt /etc/openvpn
		cp $tmp_dir/*/crl.pem /etc/openvpn
		rm -rf $tmp_dir

		#prevent OpenVPN from setting routes
		echo "route-noexec" >> /etc/openvpn/mullvad_linux.conf

		#set a script that will set routes
		echo "route-up /etc/openvpn/update-route" >> /etc/openvpn/mullvad_linux.conf
	}

	{
		echo "(I) Install OpenVPN."
		apt-get install --assume-yes openvpn resolvconf zip

		echo "(I) Configure OpenVPN"
		#mullvad "tun-ipv6" to their OpenVPN configuration file.
		case "mullvad" in
			"mullvad")
				setup_mullvad "mullvadconfig.zip"
			;;
			#apt-get install openvpn resolvconf
			*)
				echo "Unknown argument"
				exit 1
			;;
		esac

		cp etc/openvpn/update-route /etc/openvpn/
	}

	#NAT64
	{
		echo "(I) Install tayga."
		apt-get install --assume-yes tayga

		#enable tayga
		sed -i 's/RUN="no"/RUN="yes"/g' /etc/default/tayga

		echo "(I) Configure tayga"
		cp -r etc/tayga.conf /etc/
	}

	#DNS64
	{
		echo "(I) Install bind."
		apt-get install --assume-yes bind9

		echo "(I) Configure bind"
		cp -r etc/bind /etc/
		sed -i "s/fdef:17a0:ffb1:300::1/$ip_addr/g" /etc/bind/named.conf.options
	}

	#IPv6 Router Advertisments
	{
		echo "(I) Install radvd."
		apt-get install --assume-yes radvd

		echo "(I) Configure radvd"
		cp etc/radvd.conf /etc/
		sed -i "s/fdef:17a0:ffb1:300::1/$ip_addr/g" /etc/radvd.conf
		sed -i "s/fdef:17a0:ffb1:300::/$ff_prefix/g" /etc/radvd.conf
	}

	sed -i "s/gateway=\".*\"/gateway=\"true\"/g" /root/scripts/update.sh
fi

echo "done"
