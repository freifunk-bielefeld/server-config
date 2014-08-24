#!/bin/sh

#This script is called every 5 minutes via crond

#announce own piece of map information
/root/print_map.sh | alfred -s 64

#announce service as gateway
/root/print_service.sh | alfred -s 88

#collect all map pieces
alfred -r 64 > /root/maps.txt

#collect all services
alfred -r 88 > /root/services.txt

#create map data
/root/ffmap-backend.py -m /root/maps.txt -a /root/aliases.json -s /root/services.json > /var/www/nodes.json

#update nodes/clients/gateways counter
/root/counter.py '/var/www/nodes.json' '/var/www/counter.svg'
