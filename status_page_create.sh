#!/bin/bash

dst="$1"
src="/tmp/freifunk_status.tmp"

vpn_if='fastd_bat'
wan_if='vpnexit'
avg_time=5


#write stdout to file
exec >"$src" 2>&1

convert() {
  echo $1 | awk '{
  split("B,KiB,MiB,GiB,TiB,EiB,PiB,YiB,ZiB", s, ",")
  c=1; x=$1
  while (x>=1024 && c<8) {x/=1024; c++}
  xf=(c==1)?"%d":"%.2f"
  printf(xf" %s\n", x, s[c])
  }'
}

vpn_tx1_bytes=`cat "/sys/class/net/$vpn_if/statistics/tx_bytes"`
vpn_rx1_bytes=`cat "/sys/class/net/$vpn_if/statistics/rx_bytes"`
wan_tx1_bytes=`cat "/sys/class/net/$wan_if/statistics/tx_bytes"`
wan_rx1_bytes=`cat "/sys/class/net/$wan_if/statistics/rx_bytes"`

sleep $avg_time

vpn_tx2_bytes=`cat "/sys/class/net/$vpn_if/statistics/tx_bytes"`
vpn_rx2_bytes=`cat "/sys/class/net/$vpn_if/statistics/rx_bytes"`
wan_tx2_bytes=`cat "/sys/class/net/$wan_if/statistics/tx_bytes"`
wan_rx2_bytes=`cat "/sys/class/net/$wan_if/statistics/rx_bytes"`

wan_tx_speed=$((($wan_tx2_bytes-$wan_tx1_bytes)/$avg_time))
wan_rx_speed=$((($wan_rx2_bytes-$wan_rx1_bytes)/$avg_time))
vpn_tx_speed=$((($vpn_tx2_bytes-$vpn_tx1_bytes)/$avg_time))
vpn_rx_speed=$((($vpn_rx2_bytes-$vpn_rx1_bytes)/$avg_time))

wan_tx_str="`convert $wan_tx2_bytes` (`convert $wan_tx_speed`/s)"
wan_rx_str="`convert $wan_rx2_bytes` (`convert $wan_rx_speed`/s)"
vpn_tx_str="`convert $vpn_tx2_bytes` (`convert $vpn_tx_speed`/s)"
vpn_rx_str="`convert $vpn_rx2_bytes` (`convert $vpn_rx_speed`/s)"

u=`uptime`
load="${u##*:}"
u="${u%%,*}"
uptime="${u##*up}"
hdd=`df -h | grep '/$' | cut -d' ' -f 20`

echo '<html>'
echo '<head>'
echo '<title>Gateway-Status</title>'
echo '<link rel="stylesheet" type="text/css" href="status_page_style.css">'
echo '</head>'
echo '<body>'

echo '<br /><br />'
echo '<h2>Statusseite des Gateways vpn.freifunk-bielefeld.de</h2>'
echo '<center>('`date`')</center>'
echo '<table>'
echo '<tr style="vertical-align:bottom;">'
echo '<td id="left_top">'$wan_tx_str'</td>'
echo '<td id="middle_top"><b>Load:</b>'$load'<br><b>Uptime:</b>'$uptime'</td>'
echo '<td id="right_top">'$vpn_rx_str'</td>'
echo '</tr>'
echo '<tr>'
echo '<td colspan=3><img src="status_page_background.png" class="schema"></td></tr>'
echo '<tr style="vertical-align:top;">'
echo '<td id="left_bottom">'$wan_rx_str'</td>'
echo '<td id="middle_bottom"><b>HDD:</b> '$hdd'<br><a href="vnstat/">Traffic Statistics</a></td>'
echo '<td id="right_bottom">'$vpn_tx_str'</td>'
echo '</tr>'
echo '</table>'
echo '</body>'
echo '</html>'

#move to final destination
mv "$src" "$dst"

exit 0

