#!/bin/sh

#This script is called every 5 minutes via crond

#announce own piece of map information
./print_map.sh | alfred -s 64

#announce own gateway service
./print_service.sh | alfred -s 91

#collect all map pieces
alfred -r 64 > /root/maps.txt

#collect all services
alfred -r 91 > /root/services.txt

#create map data
./ffmap-backend.py -m /root/maps.txt -s /root/services.txt -a /root/aliases.json > /var/www/nodes.json

#update nodes/clients/gateways counter
./counter_update.py '/var/www/map.freifunk-bielefeld.de/nodes.json' '/var/www/freifunk-bielefeld.de/counter.svg'

#update FF-Internal status page
./status_page_create.sh '/var/www/vpn.ffbi/index.html'
