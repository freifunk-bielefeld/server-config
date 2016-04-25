#!/bin/bash

mesh_ifname='bat0' #fastd mesh
wan_ifname='tun0' #vpn uplink
avg_time=5 #seconds
name=`hostname`

if [ -n "$1" ]; then
  dst="$1"
  src="$(mktemp)"

  #write stdout to file
  exec >"$src" 2>&1
fi

convert() {
  echo $1 | awk '{
  split("B,KiB,MiB,GiB,TiB,EiB,PiB,YiB,ZiB", s, ",")
  c=1; x=$1
  while (x>=1024 && c<8) {x/=1024; c++}
  xf=(c==1)?"%d":"%.2f"
  printf(xf" %s\n", x, s[c])
  }'
}

if [ -e /sys/class/net/$mesh_ifname/address ]; then
	mesh_tx1_bytes=`cat "/sys/class/net/$mesh_ifname/statistics/tx_bytes"`
	mesh_rx1_bytes=`cat "/sys/class/net/$mesh_ifname/statistics/rx_bytes"`
fi

if [ -e /sys/class/net/$wan_ifname/address ]; then
	wan_tx1_bytes=`cat "/sys/class/net/$wan_ifname/statistics/tx_bytes"`
	wan_rx1_bytes=`cat "/sys/class/net/$wan_ifname/statistics/rx_bytes"`
fi

sleep $avg_time

if [ -e /sys/class/net/$mesh_ifname/address ]; then
	mesh_tx2_bytes=`cat "/sys/class/net/$mesh_ifname/statistics/tx_bytes"`
	mesh_rx2_bytes=`cat "/sys/class/net/$mesh_ifname/statistics/rx_bytes"`

	mesh_tx_speed=$((($mesh_tx2_bytes-$mesh_tx1_bytes)/$avg_time))
	mesh_rx_speed=$((($mesh_rx2_bytes-$mesh_rx1_bytes)/$avg_time))

	mesh_tx_str="`convert $mesh_tx2_bytes` (`convert $mesh_tx_speed`/s)"
	mesh_rx_str="`convert $mesh_rx2_bytes` (`convert $mesh_rx_speed`/s)"
else
	mesh_tx_str="-"
	mesh_rx_str="-"
fi

if [ -e /sys/class/net/$wan_ifname/address ]; then
	wan_tx2_bytes=`cat "/sys/class/net/$wan_ifname/statistics/tx_bytes"`
	wan_rx2_bytes=`cat "/sys/class/net/$wan_ifname/statistics/rx_bytes"`

	wan_tx_speed=$((($wan_tx2_bytes-$wan_tx1_bytes)/$avg_time))
	wan_rx_speed=$((($wan_rx2_bytes-$wan_rx1_bytes)/$avg_time))

	wan_tx_str="`convert $wan_tx2_bytes` (`convert $wan_tx_speed`/s)"
	wan_rx_str="`convert $wan_rx2_bytes` (`convert $wan_rx_speed`/s)"
else
	wan_tx_str="-"
	wan_rx_str="-"
fi


u="$(uptime)"
load="${u##*:}"
u="${u%%,*}"
uptime="${u##*up}"
hdd=`df -h | awk  '{ if($6=="/") { print($5); exit; } }' 2> /dev/null`

echo '<html>'
echo '<head>'
echo '<title>Gateway-Status</title>'
echo '<link rel="stylesheet" type="text/css" href="status_page_style.css">'
echo '</head>'
echo '<body>'
echo '<div>'

echo '<h2>Statusseite des Servers '$name'</h2>'
echo '<center>('`date`')</center>'
echo '<table>'
echo '<tr style="vertical-align:bottom;">'
echo '<td id="left_top">'$wan_tx_str'</td>'
echo '<td id="middle_top"><b>Load:</b>'$load'<br><b>Uptime:</b>'$uptime'</td>'
echo '<td id="right_top">'$mesh_rx_str'</td>'
echo '</tr>'
echo '<tr>'
echo '<td colspan=3><img src="status_page_background.png" class="schema"></td></tr>'
echo '<tr style="vertical-align:top;">'
echo '<td id="left_bottom">'$wan_rx_str'</td>'
echo '<td id="middle_bottom">'
echo '  <b>HDD:</b> '$hdd'<br />'
echo '  <a href="graph.html">Graph</a> / <a href="geomap.html">Karte</a> / <a href="list.html">Liste</a><br />'
echo '  <a href="counter.svg">Counter</a>'
echo '</td>'
echo '<td id="right_bottom">'$mesh_tx_str'</td>'
echo '</tr>'
echo '</table>'

echo '</div>'
echo '</body>'
echo '</html>'

if [ -n "$1" ]; then
  #change group/owner to webserver
  chown www-data:www-data "$src"

  #move to final destination
  mv "$src" "$dst"
fi
