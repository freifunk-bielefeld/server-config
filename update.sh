#!/bin/sh

#This script is called every 5 minutes via crond

#publish own piece of map information
/root/print_map.sh | alfred -s 64

#collect all map pieces
alfred -r 64 > /root/maps.txt

#create map data
/root/ffmap-backend.py -m /root/maps.txt -a /root/aliases.json > /var/www/nodes.json

#update nodes/clients/gateways counter
/root/counter.py '/var/www/nodes.json' '/var/www/counter.svg'
