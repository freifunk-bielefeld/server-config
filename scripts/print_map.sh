#!/bin/sh

#Print out local connection data for map creation

geo="" #e.g. "52.02513078 8.55887"
name="$(hostname)"
firmware=""
community=""
gateway="" #e.g. true / false

echo -n "{"

[ -n "$geo" ] && echo -n "\"geo\" : \"$geo\", "
[ -n "$name" ] && echo -n "\"name\" : \"$name\", "
[ -n "$firmware" ] && echo -n "\"firmware\" : \"$firmware\", "
[ -n "$community" ] && echo -n "\"community\" : \"$community\", "
[ -n "$gateway" ] && echo -n "\"gateway\" : $gateway, "

echo -n "\"links\" : ["

printLink() { echo -n "{ \"smac\" : \"$(cat /sys/class/net/$3/address)\", \"dmac\" : \"$1\", \"qual\" : $2 }"; }
IFS="
"
nd=0
for entry in $(cat /sys/kernel/debug/batman_adv/bat0/originators |  tr '\t/[]()' ' ' |  awk '{ if($1==$4) print($1, $3, $5) }'); do
  [ $nd -eq 0 ] && nd=1 || echo -n ", "
  IFS=" "
  printLink $entry
done

echo -n '], '
echo -n "\"clientcount\" : 0"
echo -n '}'
