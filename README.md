Freifunk-Bielefeld Server
===============

Scripte und Konfigurationsdateien zum schnellen Einrichten eines Freifunk-Servers.
Vorausgesetzt wird Debian Wheezy mit wheezy-backports.

server_setup.sh richtet einen Server ein, der Teil des Bielefeld Freifunk Netzes ist.
Es werden folgende wesentlichen Programme installiert und konfiguriert:

 * Routingprotokoll: [batman-adv](http://www.open-mesh.org/projects/batman-adv/wiki)
 * FF-VPN: [fastd](https://projects.universe-factory.net/projects/fastd/wiki)
 * Webserver: lighttpd
 * Karte: [ffmap](https://github.com/ffnord/ffmap-d3)

setup_gateway.sh richtet einen mit server_setup.sh eingerichteten Server so ein,
das er als Gateway im Bielefelder Freifunk-Netz dient. Das Script erwartet die Accountdaten
von mullvad.net oder ipredator.se im gleichen Verzeichnis.
Es werden folgende wesentlichen Programme installiert und konfiguriert:

 * NAT64: [tayga](http://www.litech.org/tayga/)
 * DNS64: bind
 * IPv6 Router Advertisment: radvd
 * Auslands-VPN: OpenVPN


Zu Ausführen einfach als Benutzer 'root' die Scripte ausführen:

<pre>
git clone https://github.com/freifunk-bielefeld/server-config.git
cd server-config
./setup_server.sh
</pre>
