#!/bin/bash

wan_iface="eth0"
ff_prefix="fdef:17a0:ffb1:300::" #internal nework prefix
run=0 #set to 1 for this script to run

#####################################

echo "This script is not complete yet."
exit 1

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

setup_mullvad() {
	local mullvad_zip="$1"
	local dir="/tmp/mullvadconfig"

	if [ ! -f "$mullvad_zip" ]; then
		echo "Mullvad zip file missing: $mullvad_zip"
		exit 1
	fi

	#unzip and copy files to OpenVPN
	rm -rf $dir
	unzip $mullvad_zip -d $dir/etc/openvpn
	cp $dir/*/mullvad_linux.conf /etc/openvpn
	cp $dir/*/mullvad.key /etc/openvpn
	cp $dir/*/mullvad.crt /etc/openvpn
	cp $dir/*/ca.crt /etc/openvpn
	cp $dir/*/crl.pem /etc/openvpn
	rm -rf $dir

	#prevent OpenVPN from setting routes
	echo "route-noexec" >> /etc/openvpn/mullvad_linux.conf

	#set a script that will set routes
	echo "route-up /etc/openvpn/update-route" >> /etc/openvpn/mullvad_linux.conf
}

if ! is_installed "openvpn"; then
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
	#check for /etc/config/openvpn/
	cp etc/openvpn/
fi

#NAT64
if ! is_installed "tayga"; then
	echo "(I) Install tayga."
	apt-get install --assume-yes tayga

	echo "(I) Configure tayga"
	cp -r etc/tayga.conf /etc/

	#enable tayga
	sed -i 's/RUN="no"/RUN="yes"/g' /etc/default/tayga

	#set dynamic-pool for ICVPN
	server_num=3 #hm...
	sed -i "s/10.26.0./10.26.$((($server_num - 1) * 8))./g" /etc/tayga.conf
fi

if ! is_running "tayga"; then
  echo "(I) Start tayga."
  /etc/init.d/tayga start
fi

#DNS64
if ! is_installed "bind"; then
	echo "(I) Install bind."
	apt-get install --assume-yes bind9

	echo "(I) Configure bind"
	cp -r etc/bind /etc/
fi

if ! is_running "named"; then
  echo "(I) Start bind."
  /etc/init.d/bind9 start
fi
