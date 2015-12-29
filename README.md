Freifunk-Ulm Server
===============

Scripte und Konfigurationsdateien zum schnellen Einrichten eines Servers für Freifunk-Ulm.
Vorausgesetzt wird eine Debian 8 Installation (Jessie).
Um einen Server einzurichten, reicht es, das Script setup_server.sh als Benutzer 'root' auszuführen:

```
apt-get install git
git clone https://github.com/ffulm/server-config.git
cd server-config
./setup_server.sh
```

Nach erfolgreichem Einrichten wird das Script /opt/freifunk/update.sh alle 5 Minuten
von crond aufgerufen. Dadurch wird die Karte regelmäßig aktualisiert und z.B. nach
einem Neustart notwendige Programme neu gestartet.

Für die Serverfunktion werden folgende Programme installiert und konfiguriert:

 * Routingprotokoll: [batman-adv](http://www.open-mesh.org/projects/batman-adv/wiki)
 * FF-VPN: [fastd](https://projects.universe-factory.net/projects/fastd/wiki)
 * Webserver: lighttpd
 * Karte: [ffmap](https://github.com/ffnord/ffmap-d3)

Wird die entsprechende Variable im Setup-Script auf true gesetzt, wird der Server gleich auch
als Gateway eingerichtet. Das Script erwartet dann eine ZIP-Datei mit den Accountdaten
von mullvad.net im gleichen Verzeichnis. Zum Testen eignet sich ein anonymer Testaccount
für drei Stunden.

Ansonsten werden für die Gatewayfunktion folgende Programme installiert und konfiguriert:

 * NAT64: [tayga](http://www.litech.org/tayga/)
 * DNS64: bind
 * IPv6 Router Advertisment: radvd
 * Auslands-VPN: OpenVPN

Durch die Reaktivierung von IPv4 im Freifunk Netz werden weitere Dienste benötigt:
 * DHCP (isc-dhcp-server)

Alle Serverbetreiber müssen sich absprechen, was den Bereich der verteilten DHCP Adressen angeht, damit es zu keinen Adresskonflikten kommt. Bisher wurden folgende Bereiche vergeben:

 * vpn1: 10.33.64.1 range 10.33.64.2 10.33.67.255
 * vpn2: 10.33.68.1 range 10.33.68.2 10.33.71.255
 * vpn3: 10.33.72.1 range 10.33.72.2 10.33.75.255
 * vpn4: 10.33.76.1 range 10.33.76.2 10.33.79.255
 * vpn5: 10.33.80.1 range 10.33.80.2 10.33.83.255
 * vpn6: 10.33.84.1 range 10.33.84.2 10.33.87.255
 
Innerhalb des Freifunknetzes gibt es die DNS Zone ".ffulm". D.h. es können auch Namen wie "meinserver.ffulm" aufgelöst werden. Masterserver dafür ist zur Zeit vpn5.
Falls weitere Server hinzugefügt werden, müssen die Zonendateien auf dem Master (db.10.33, db.ffulm, named.conf.local) manuell angepasst werden. Hierzu bitte auf der Mailingliste melden.

Des Weiteren sollte mindestens ein Server mit dem Schalter "-m" als "Master" betrieben werden. Zur Zeit ist dies VPN6.
https://github.com/ffulm/server-config/blob/master/freifunk/update.sh#L121

Freifunk Ulm nutzt folgende Netze:
 * ipv4: 10.33.0.0/16
 * ipv6: fdef:17a0:fff1::/48
 
Durchsatz und Statistiken
-----
Es wird vnstat und munin auf den Servern verwendet. Wenn dies nicht gewünscht wird muss die Variable setup_statistics auf "no" gesetzt werden.
```
apt-get install munin
cd /var/www
ln -s /var/cache/munin/www/munin
```
Dann unter /etc/munin.conf anpassen:
```
#[localhost.localdomain]
#    address 127.0.0.1
#    use_node_name yes
[vpn1.ffulm]
     address 10.33.64.1
[vpn2.ffulm]
     address 10.33.68.1
[vpn3.ffulm]
     address 10.33.72.1
[vpn4.ffulm]
     address 10.33.76.1
[vpn5.ffulm]
     address 127.0.0.1
[vpn6.ffulm]
     address 10.33.84.1
```
Daemon neustarten
```
/etc/init.d/munin restart
```

ICVPN
-----

Tinc aus Debian jessie ist (angeblich) nicht stabil genug.

Doku zu ICVPN bei FF Bielefeld:
https://wiki.freifunk-bielefeld.de/doku.php?id=ic-vpn

Tinc 1.11 pre selbst bauen:
https://gist.github.com/mweinelt/efff4fb7eba1ee41ef2d

ICVPN im Freifunk wiki:
https://wiki.freifunk.net/IC-VPN
