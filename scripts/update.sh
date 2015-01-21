#!/bin/sh

#This script is called every 5 minutes via crond

cd /root/scripts/

#announce own piece of map information
./print_map.sh | gzip -c - | alfred -s 64

#announce own gateway service
./print_service.sh | alfred -s 91

#collect all map pieces
alfred -r 64 > /tmp/maps.txt

#collect all services
alfred -r 91 > /tmp/services.txt

#create map data
./ffmap-backend.py -m /tmp/maps.txt -a ./aliases.json > /var/www/map/nodes.json

#update nodes/clients/gateways counter
./counter_update.py '/var/www/map/nodes.json' '/var/www/counter/counter_image.svg'

#update FF-Internal status page
./status_page_create.sh '/var/www/status/index.html'
