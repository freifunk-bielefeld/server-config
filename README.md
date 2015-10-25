Freifunk-Ulm Server
===============

Scripte und Konfigurationsdateien zum schnellen Einrichten eines Servers für Freifunk-Ulm.
Vorausgesetzt wird eine Debian 8 Installation (Jessie).
Um einen Server einzurichten, reicht es, das Script setup_server.sh als Benutzer 'root' auszuführen:

```
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

 * vpn3: 10.33.72.1 range 10.33.72.2 10.33.75.255
 * vpn5: 10.33.80.1 range 10.33.80.2 10.33.83.255
 * vpn6: 10.33.84.1 range 10.33.84.2 10.33.87.255
 
Innerhalb des Freifunknetzes gibt es die DNS Zone ".ffulm". D.h. es können auch Namen wie "meinserver.ffulm" aufgelöst werden. Masterserver dafür ist zur Zeit vpn6.
Falls weitere Server hinzugefügt werden, müssen die Zonendateien auf dem Master (db.10.33, db.ffulm, named.conf.local) manuell angepasst werden. Hierzu bitte auf der Mailingliste melden.

Freifunk Ulm nutzt folgende Netze:
 * ipv4: 10.33.0.0/16
 * ipv6: fdaf:17a0:fff1::/48
 
