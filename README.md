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
