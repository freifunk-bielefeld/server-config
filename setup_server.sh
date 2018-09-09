#!/bin/bash

#This script sets up a Freifunk server consisting
#of batman-adv, fastd and a web server for the status site.

#Secret key for fastd (optional).
fastd_secret=""

#The servers Internet interface.
wan_iface="eth0"

#The community identifier.
community_id="bielefeld"
community_name="Bielefeld"

#The internal IPv6 prefix
ff_prefix="fdef:17a0:ffb1:300::"

#setup map/counter/status page
setup_webserver="true"

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
apt update

{
	echo "(I) Create /opt/freifunk/"
	apt install --assume-yes python3 python3-jsonschema
	cp -rf freifunk /opt/

	sed -i "s/ip_addr=\".*\"/ip_addr=\"$ip_addr\"/g" /opt/freifunk/update.sh
	sed -i "s/mac_addr=\".*\"/mac_addr=\"$mac_addr\"/g" /opt/freifunk/update.sh
	sed -i "s/community=\".*\"/community=\"$community_id\"/g" /opt/freifunk/update.sh
	sed -i "s/ff_prefix=\".*\"/ff_prefix=\"$ff_prefix\"/g" /opt/freifunk/update.sh
}

if [ "$setup_webserver" = "true" ]; then
	{
		echo "(I) Install lighttpd"
		apt install --assume-yes lighttpd
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

		echo "(I) Install Meshviewer Map"
		apt install --assume-yes make git yarn
		git clone https://github.com/ffrgb/meshviewer
		cp meshviewer_config/config.js meshviewer/
		cp meshviewer_config/config.default.js meshviewer/
		cp meshviewer_config/scss/custom/custom.scss meshviewer/scss/custom/
		cd meshviewer
		yarn
		cp -r build /var/www/meshviewer
		mkdir -p /var/www/meshviewer/data
		cd ..
		rm -rf meshviewer

		chown -R www-data:www-data /var/www
	}

	sed -i "s/webserver=\".*\"/webserver=\"true\"/g" /opt/freifunk/update.sh
fi

if [ -z "$(cat /etc/crontab | grep '/opt/freifunk/update.sh')" ]; then
	echo "(I) Add entry to /etc/crontab"
	echo '*/5 * * * * root /opt/freifunk/update.sh > /dev/null' >> /etc/crontab
fi

{
	VERSION=2016.1

	echo "(I) Install batman-adv, batctl and alfred ($VERSION)."
	apt install --assume-yes wget build-essential linux-headers-$(uname -r) pkg-config libnl-3-dev libjson-c-dev git libcap-dev pkg-config

	#install batman-adv
	wget --no-check-certificate http://downloads.open-mesh.org/batman/releases/batman-adv-$VERSION/batman-adv-$VERSION.tar.gz
	sha256check "batman-adv-$VERSION.tar.gz" "518dc228dfd3fcc1ea1c6af7c32aceb19ab67810983d82473891ce3605daa072"
	tar -xzf batman-adv-$VERSION.tar.gz
	cd batman-adv-$VERSION/
	make
	make install
	cd ..
	rm -rf batman-adv-$VERSION*

	#install batctl
	wget --no-check-certificate http://downloads.open-mesh.org/batman/releases/batman-adv-$VERSION/batctl-$VERSION.tar.gz
	sha256check "batctl-$VERSION.tar.gz" "c854397b2ddd2cb8d15d1e65839819380648ccb37507d0303e133011fe6f03c9"
	tar -xzf batctl-$VERSION.tar.gz
	cd batctl-$VERSION/
	make
	make install
	cd ..
	rm -rf batctl-$VERSION*

	#install alfred
	wget --no-check-certificate http://downloads.open-mesh.org/batman/stable/sources/alfred/alfred-$VERSION.tar.gz
	sha256check "alfred-$VERSION.tar.gz" "7e0efaf263d6772e5e23bdad933f676951cd03124382e6dbae53a7b9431d2609"
	tar -xzf alfred-$VERSION.tar.gz
	cd alfred-$VERSION/
	make CONFIG_ALFRED_GPSD=n CONFIG_ALFRED_VIS=n CONFIG_ALFRED_CAPABILITIES=n
	make CONFIG_ALFRED_GPSD=n CONFIG_ALFRED_VIS=n CONFIG_ALFRED_CAPABILITIES=n install
	cd ..
	rm -rf alfred-$VERSION*
}

{
	echo "(I) Install fastd."

	apt install --assume-yes git cmake-curses-gui libnacl-dev flex bison libcap-dev pkg-config zip libjson-c-dev

	#install libsodium
	wget --no-check-certificate https://github.com/jedisct1/libsodium/releases/download/1.0.5/libsodium-1.0.5.tar.gz
	sha256check "libsodium-1.0.5.tar.gz" "bfcafc678c7dac87866c50f9b99aa821750762edcf8e56fc6d13ba0ffbef8bab"
	tar -xvzf libsodium-1.0.5.tar.gz
	cd libsodium-1.0.5
	./configure
	make
	make install
	cd ..
	rm -rf libsodium-1.0.5*
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
}

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
		apt install --assume-yes netfilter-persistent

		cp -rf etc/iptables/* /etc/iptables/
		/etc/init.d/netfilter-persistent restart
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
		apt install --assume-yes openvpn resolvconf zip

		echo "(I) Configure OpenVPN"
		#mullvad "tun-ipv6" to their OpenVPN configuration file.
		case "mullvad" in
			"mullvad")
				setup_mullvad "mullvadconfig.zip"
			;;
			#apt install openvpn resolvconf
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
		apt install --assume-yes tayga

		#enable tayga
		sed -i 's/RUN="no"/RUN="yes"/g' /etc/default/tayga

		echo "(I) Configure tayga"
		cp -r etc/tayga.conf /etc/
	}

	#DNS64
	{
		echo "(I) Install bind."
		apt install --assume-yes bind9

		echo "(I) Configure bind"
		cp -r etc/bind /etc/bind/
		sed -i "s/fdef:17a0:ffb1:300::1/$ip_addr/g" /etc/bind/named.conf.options
	}

	#IPv6 Router Advertisments
	{
		echo "(I) Install radvd."
		apt install --assume-yes radvd

		echo "(I) Configure radvd"
		cp etc/radvd.conf /etc/
		sed -i "s/fdef:17a0:ffb1:300::1/$ip_addr/g" /etc/radvd.conf
		sed -i "s/fdef:17a0:ffb1:300::/$ff_prefix/g" /etc/radvd.conf
	}

	sed -i "s/gateway=\".*\"/gateway=\"true\"/g" /opt/freifunk/update.sh
fi

echo "done"

/opt/freifunk/update.sh
