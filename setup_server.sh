#!/bin/bash

#This script sets up a Freifunk server consisting
#of batman-adv, fastd and a web server for the status site.

#Secret key for fastd (optional).
fastd_secret=""

#The servers Internet interface.
wan_iface="eth0"

#The community identifier.
community_id="ulm"
community_name="Ulm"

#The internal IPv6 prefix
ff_prefix="fdef:17a0:fff1:300::"

#setup map/counter/status page
setup_webserver="true"

#setup a gateway with http://mullvad.net
setup_gateway="false"

#setup statistics
# webserver must be enabled for this to work
setup_statistics="true"

#setup icvpn dns updates
# get daily updates of intercity vpn dns zones for bind9
setup_icvpn_dns="true"

#IP v4 for mesh interface.
#This is gateway specific. Get your IP by writing to the mailing list!
#Format: xxx.xxx.xxx.xxx
ipv4_mesh_interface=""

#range for DHCP
#This is gateway specific. Get your DHCP range by writing to the mailing list!
#Enter space separated IP range: xxx.xxx.xxx.xxx xxx.xxx.xxx.xxx
ipv4_dhcp_range=""

#Set to 1 for this script to run. :-)
# Make sure to set content of /etc/hostname to vpnX.freifunk-ulm.de scheme
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
	echo "(I) Create /opt/freifunk/"
	apt-get install --assume-yes python3 python3-jsonschema
	cp -rf freifunk /opt/
	
	# transfer several constants to update.sh
	sed -i "s/ip_addr=\".*\"/ip_addr=\"$ip_addr\"/g" /opt/freifunk/update.sh
	sed -i "s/mac_addr=\".*\"/mac_addr=\"$mac_addr\"/g" /opt/freifunk/update.sh
	sed -i "s/community=\".*\"/community=\"$community_id\"/g" /opt/freifunk/update.sh
	sed -i "s/ff_prefix=\".*\"/ff_prefix=\"$ff_prefix\"/g" /opt/freifunk/update.sh
	sed -i "s/ipv4_mesh_interface=\".*\"/ipv4_mesh_interface=\"$ipv4_mesh_interface\"/g" /opt/freifunk/update.sh
}

if [ "$setup_webserver" = "true" ]; then
	{
		echo "(I) Install lighttpd"
		apt-get install --assume-yes lighttpd
		# generate strong DH primes
		openssl dhparam -out /etc/ssl/certs/dhparam.pem 4096
	}

	{
		echo "(I) Create /etc/lighttpd/lighttpd.conf"
		cp etc/lighttpd/lighttpd.conf /etc/lighttpd/
		sed -i "s/fdef:17a0:fff1:300::1/$ip_addr/g" /etc/lighttpd/lighttpd.conf
		sed -i "s/SERVERNAME/$(hostname)/g" /etc/lighttpd/lighttpd.conf
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
		sed -i "s/ffbi-/ffulm-/g" config.js
		sed -i "s/gotham.freifunk.net/www.freifunk-$community_id.de/g" config.js
		sed -i "s/gotham/$community_id/g" config.js
		sed -i "s/Gotham/$community_name/g" config.js
		sed -i "s/fdef:17a0:ffb1:300::/$ff_prefix/g" config.js
		make
		cp -r www/* /var/www/
		cd ..
		rm -rf ffmap-d3

		chown -R www-data:www-data /var/www
	}

	{
		# get letsencrypt client
		echo "(I) Populate /opt/letsencrypt/"
		git clone https://github.com/letsencrypt/letsencrypt /opt/letsencrypt/
		# copy cert renewal script
		cp -r opt/letsencrypt/* /opt/letsencrypt/
		mkdir -p /var/log/letsencrypt/
		touch /var/log/letsencrypt/renew.log

		# call once to get initial cert
		echo "(I) Get Letsencrypt Certificate... This can take some time!"
		/opt/letsencrypt/check_update_ssl.sh

		# add letsencrypt certificate renewal script to crontab
		if [ -z "$(cat /etc/crontab | grep '/opt/letsencrypt/check_update_ssl.sh')" ]; then
			echo "(I) Add certificate check entry to /etc/crontab"
			echo '0 3 * * * root /opt/letsencrypt/check_update_ssl.sh > /dev/null' >> /etc/crontab
		fi
	}

	sed -i "s/webserver=\".*\"/webserver=\"true\"/g" /opt/freifunk/update.sh
	else if [ "$setup_webserver" != "true" ]; then
		sed -i "s/webserver=\".*\"/webserver=\"false\"/g" /opt/freifunk/update.sh
	fi
fi

if [ "$setup_webserver" = "true" ] && [ "$setup_statistics" = "true" ]; then
	echo "stats: Setup statistic client (vnstat/munin)"
	apt-get install --assume-yes php5-cgi vnstat munin-node
	cp -f etc/vnstat.conf /etc/
	cp -f etc/munin/munin-node.conf /etc/munin/
	# substitute hostname in munin-node.conf
	host=`echo $(hostname) | cut -f1 -d"."`
	sed -i "s/host_name\ vpnX/host_name\ $host/g" /etc/munin/munin-node.conf
	# add vnstat interface for main NIC
	vnstat -u -i eth0
	# grant access for vnstat
	chown vnstat.vnstat /var/lib/vnstat/eth0
else if [ "$setup_statistics" != "true" ]; then
	echo "stats: no statistics configured"
	# set switch to "false" in update.sh
	sed -i "s/statistics=\".*\"/statistics=\"false\"/g" /opt/freifunk/update.sh
     fi
fi

if [ "$setup_icvpn_dns" = "true" ]; then
	echo "icvpn dns: Install git and python yaml package"
	apt-get install --assume-yes git sudo python-yaml
	echo "icvpn dns: Copy cron daily file"
	cp -f etc/cron.daily/icvpn-dns-update /etc/cron.daily/
	echo "icvpn dns: Clone icvpn-meta"
	git clone https://github.com/freifunk/icvpn-meta /var/lib/icvpn-meta
	echo "icvpn dns: Clone icvpn-scripts"
	git clone https://github.com/freifunk/icvpn-scripts /opt/icvpn-scripts
fi

if [ -z "$(cat /etc/crontab | grep '/opt/freifunk/update.sh')" ]; then
	echo "(I) Add update.sh entry to /etc/crontab"
	echo '*/5 * * * root /opt/freifunk/update.sh > /dev/null' >> /etc/crontab
fi

{
	echo "(I) Install DHCP server"
	apt-get install --assume-yes isc-dhcp-server
	cp -f etc/dhcp/dhcpd.conf /etc/dhcp/
	cp -f etc/dhcp/isc-dhcp-server /etc/default/
	sed -i "s/DNS_SERVER/$ipv4_mesh_interface/g" /etc/dhcp/dhcpd.conf
	sed -i "s/DHCP_RANGE/$ipv4_dhcp_range/g" /etc/dhcp/dhcpd.conf
}

{
	VERSION=2015.1

	echo "(I) Install batman-adv, batctl and alfred ($VERSION)."
	apt-get install --assume-yes wget build-essential linux-headers-$(uname -r) pkg-config libnl-3-dev libjson-c-dev git libcap-dev pkg-config

	#install batman-adv
	wget --no-check-certificate http://downloads.open-mesh.org/batman/releases/batman-adv-$VERSION/batman-adv-$VERSION.tar.gz
	sha256check "batman-adv-$VERSION.tar.gz" "62ff9b769ada746e7a373a048ca8036fbd73f81c63053bbbe25fa24b4343dd0d"
	tar -xzf batman-adv-$VERSION.tar.gz
	cd batman-adv-$VERSION/
	make
	make install
	cd ..
	rm -rf batman-adv-$VERSION*

	#install batctl
	wget --no-check-certificate http://downloads.open-mesh.org/batman/releases/batman-adv-$VERSION/batctl-$VERSION.tar.gz
	sha256check "batctl-$VERSION.tar.gz" "ea67ee22785e6fcd5149472bdf2df4e9f21716968e025e7dd41556a010a8d14a"
	tar -xzf batctl-$VERSION.tar.gz
	cd batctl-$VERSION/
	make
	make install
	cd ..
	rm -rf batctl-$VERSION*

	#install alfred
	wget --no-check-certificate http://downloads.open-mesh.org/batman/stable/sources/alfred/alfred-$VERSION.tar.gz
	sha256check "alfred-$VERSION.tar.gz" "e2464175174beeb582564a3487346d6cf5d4de28a23ac04c2ff249099ba2b487"
	tar -xzf alfred-$VERSION.tar.gz
	cd alfred-$VERSION/
	make CONFIG_ALFRED_GPSD=n CONFIG_ALFRED_VIS=n
	make CONFIG_ALFRED_GPSD=n CONFIG_ALFRED_VIS=n install
	cd ..
	rm -rf alfred-$VERSION*
}

{
	# set capablilities for alfred binary (create sockets and use elevated privs)
	# got reset by installation of new alfred binary above
	# (FYI: dropping of privileges is possible since alfred version 2015.0)
	setcap cap_net_raw+ep `which alfred`

	# create alfred group
	addgroup --system alfred

	echo "(I) Create user alfred for alfred daemon."
	adduser --system --home /var/run/alfred --shell /bin/false --ingroup alfred --disabled-password alfred
}

{
	echo "(I) Install fastd."

	apt-get install --assume-yes git cmake-curses-gui libnacl-dev flex bison libcap-dev pkg-config zip libjson-c-dev

	#install libsodium
	wget --no-check-certificate http://github.com/jedisct1/libsodium/releases/download/1.0.5/libsodium-1.0.5.tar.gz
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
	wget --no-check-certificate https://projects.universe-factory.net/attachments/download/83 -O libuecc-6.tar.xz
	sha256check "libuecc-6.tar.xz" "a9728cf7f18968dba3930ffede7721a5a11a1fecabe2193ec4d2d63e54ceb3fb"
	tar xf libuecc-6.tar.xz
	mkdir libuecc_build
	cd libuecc_build
	cmake ../libuecc-6
	make
	make install
	cd ..
	rm -rf libuecc_build libuecc-6*
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

		#only really needed for a gateway
		echo "(I) Installing persistent iptables"
		apt-get install --assume-yes iptables-persistent

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
		# set restrictive access rights on key file
		chmod 600 /etc/openvpn/mullvad.key
		cp $tmp_dir/*/mullvad.crt /etc/openvpn
		cp $tmp_dir/*/ca.crt /etc/openvpn
		cp $tmp_dir/*/crl.pem /etc/openvpn
		rm -rf $tmp_dir

		#prevent OpenVPN from setting routes
		echo "route-noexec" >> /etc/openvpn/mullvad_linux.conf

		# prevent OpenVPN from changing nameservers in resolv.conf
	        sed -i "s|up /etc/openvpn/update-resolv-conf|#up /etc/openvpn/update-resolv-conf|g" /etc/openvpn/mullvad_linux.conf
	        sed -i "s|down /etc/openvpn/update-resolv-conf|#down /etc/openvpn/update-resolv-conf|g" /etc/openvpn/mullvad_linux.conf

		#set a script that will set routes
		echo "route-up /etc/openvpn/update-route" >> /etc/openvpn/mullvad_linux.conf
		
		#use servers in Sweden only
		sed -i 's/^remote /#remote /' /etc/openvpn/mullvad_linux.conf
		sed -i 's/^#remote se.mullvad.net/remote se.mullvad.net/' /etc/openvpn/mullvad_linux.conf
	}

	{
		echo "(I) Install OpenVPN."
		apt-get install --assume-yes openvpn resolvconf zip

		# make sure openvpn is stopped
		# otherwise update-route will never be called resulting in missing iptable rules
		/etc/init.d/openvpn stop

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
		# substitute gateway specific IP for DNS on bat0 in routes
		sed -i "s/DNS_SERVER/$ipv4_mesh_interface/g" /etc/openvpn/update-route
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
		# copy config files to destination
		cp -r etc/bind/named.* /etc/bind/
		# grant write access for zone transfers
		chmod g+w /etc/bind/
		# adjust config
		sed -i "s/fdef:17a0:fff1:300::1/$ip_addr/g" /etc/bind/named.conf.options
		sed -i "s/DNS_SERVER/$ipv4_mesh_interface/g" /etc/bind/named.conf.options
	}

	#IPv6 Router Advertisments
	{
		echo "(I) Install radvd."
		apt-get install --assume-yes radvd

		echo "(I) Configure radvd"
		cp etc/radvd.conf /etc/
		sed -i "s/fdef:17a0:fff1:300::1/$ip_addr/g" /etc/radvd.conf
		sed -i "s/fdef:17a0:fff1:300::/$ff_prefix/g" /etc/radvd.conf
	}

        # statistics
        if [ "$setup_statistics" = "true" ]; then
          # make sure tun0 is actually there for next command to work
          service openvpn start
          sleep 15
          echo "(I) Waiting for interface tun0 to start up..."
          # add vnstat interface for tun0
          vnstat -u -i tun0
	  # grant access for vnstat
	  chown vnstat.vnstat /var/lib/vnstat/tun0
        fi
	

	sed -i "s/gateway=\".*\"/gateway=\"true\"/g" /opt/freifunk/update.sh
fi

/opt/freifunk/update.sh

echo "setup done"

