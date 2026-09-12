#!/bin/sh
# ===================================================================
# ANONIMO'S VAULT OS - ONE-CLICK INSTALLER (PRODUCTION READY)
# ===================================================================

echo "====================================================="
echo "  INITIALIZING VAULT OS INSTALLATION..."
echo "====================================================="

echo "[1/8] Updating OpenWrt packages and installing PHP..."
opkg update
opkg install php8 php8-cgi php8-mod-session curl wget-ssl tar conntrack

echo "[2/8] Unlocking PHP Engine for RAM-Disk Execution..."
# Aggressively remove path restrictions from PHP
sed -i 's/.*docroot.*/docroot = ""/g' /etc/php.ini
sed -i 's/.*cgi.fix_pathinfo.*/cgi.fix_pathinfo=1/g' /etc/php.ini

echo "[3/8] Creating Bridge Devices & Splitting Physical LAN Ports..."
uci set network.br_guest=device
uci set network.br_guest.name='br-guest'
uci set network.br_guest.type='bridge'

LAN_DEV=$(uci show network | grep "name='br-lan'" | cut -d. -f2 | head -n1)
[ -z "$LAN_DEV" ] && LAN_DEV="@device[0]"

for port in lan1 lan2 lan3 lan4 lan5; do
    uci del_list network.$LAN_DEV.ports="$port" 2>/dev/null
done

LAN_PORTS=$(ls /sys/class/net | grep -E '^lan[0-9]+$' | sort)
PORT_COUNT=$(echo $LAN_PORTS | wc -w)

if [ "$PORT_COUNT" -ge 2 ]; then
    HALF=$((PORT_COUNT / 2))
    CURRENT=1
    for PORT in $LAN_PORTS; do
        if [ "$CURRENT" -le "$HALF" ]; then
            uci add_list network.$LAN_DEV.ports="$PORT"
        else
            uci add_list network.br_guest.ports="$PORT"
        fi
        CURRENT=$((CURRENT + 1))
    done
elif [ "$PORT_COUNT" -eq 1 ]; then
    uci add_list network.$LAN_DEV.ports="$LAN_PORTS"
fi

uci set network.guest=interface
uci set network.guest.device='br-guest'
uci set network.guest.proto='static'
uci set network.guest.ipaddr='10.0.0.1'
uci set network.guest.netmask='255.255.255.0'
uci commit network

echo "[4/8] Configuring DHCP Pool & Firewall Zones..."
uci set dhcp.guest=dhcp
uci set dhcp.guest.interface='guest'
uci set dhcp.guest.start='100'
uci set dhcp.guest.limit='200'
uci set dhcp.guest.leasetime='12h'
uci commit dhcp

uci add firewall zone
uci set firewall.@zone[-1].name='guest'
uci set firewall.@zone[-1].network='guest'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci commit firewall

echo "[5/8] Configuring uHTTPd Dual-Server (Fixing LuCI & Portal)..."
# 1. Lock LuCI exclusively to the Admin LAN (192.168.1.1)
uci set uhttpd.main.home='/www'
uci set uhttpd.main.cgi_prefix='/cgi-bin'
uci del uhttpd.main.listen_http 2>/dev/null
uci add_list uhttpd.main.listen_http='192.168.1.1:80'
uci del uhttpd.main.listen_https 2>/dev/null
uci add_list uhttpd.main.listen_https='192.168.1.1:443'
uci add_list uhttpd.main.interpreter='.php=/usr/bin/php-cgi'

# 2. Lock Vault OS exclusively to the Guest WiFi (10.0.0.1)
uci set uhttpd.portal=uhttpd
uci del uhttpd.portal.listen_http 2>/dev/null
uci add_list uhttpd.portal.listen_http='10.0.0.1:80'
uci set uhttpd.portal.home='/tmp/html'
uci set uhttpd.portal.index_page='index.php'
uci del uhttpd.portal.error_page 2>/dev/null
uci add_list uhttpd.portal.error_page='404=/index.php'
uci add_list uhttpd.portal.interpreter='.php=/usr/bin/php-cgi'
uci commit uhttpd

echo "[6/8] Configuring Dual-Band Wi-Fi (Piso WiFi & Admin LAN)..."
while uci -q delete wireless.@wifi-iface[0]; do :; done

for radio in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1); do
    band=$(uci -q get wireless.$radio.band)
    hwmode=$(uci -q get wireless.$radio.hwmode)
    
    if [ "$band" = "5g" ] || [ "$band" = "a" ] || [ "$hwmode" = "11a" ] || [ "$hwmode" = "11ac" ] || [ "$hwmode" = "11ax5g" ]; then
        SUFFIX="5G"
    else
        SUFFIX="2.4G"
    fi

    uci add wireless wifi-iface
    uci set wireless.@wifi-iface[-1].device="$radio"
    uci set wireless.@wifi-iface[-1].network='lan'
    uci set wireless.@wifi-iface[-1].mode='ap'
    uci set wireless.@wifi-iface[-1].ssid="NIMOS MAIN $SUFFIX"
    uci set wireless.@wifi-iface[-1].encryption='psk2'
    uci set wireless.@wifi-iface[-1].key='01234567'

    uci add wireless wifi-iface
    uci set wireless.@wifi-iface[-1].device="$radio"
    uci set wireless.@wifi-iface[-1].network='guest'
    uci set wireless.@wifi-iface[-1].mode='ap'
    uci set wireless.@wifi-iface[-1].ssid="ANONIMO'S PISO WIFI $SUFFIX"
    uci set wireless.@wifi-iface[-1].encryption='none'
    uci set wireless.$radio.disabled='0'
done
uci commit wireless
wifi reload

echo "[7/8] Writing Firewall Engine (vaultos_core.sh)..."
cat << 'EOF_VAULT' > /etc/vaultos_core.sh
#!/bin/sh
# ANONIMO'S VAULT OS - OPENWRT NFTABLES CORE

echo "Vault OS initializing..."

chmod +s /usr/sbin/nft 2>/dev/null
chmod +s /usr/sbin/conntrack 2>/dev/null

nft delete table inet pisowifi 2>/dev/null
nft add table inet pisowifi
nft add set inet pisowifi authenticated_macs { type ether_addr\; }
nft add set inet pisowifi wisp_macs { type ether_addr\; }

nft add chain inet pisowifi captive_portal { type nat hook prerouting priority dstnat - 1\; policy accept\; }
nft add rule inet pisowifi captive_portal ether saddr @authenticated_macs return
nft add rule inet pisowifi captive_portal ether saddr @wisp_macs return
nft add rule inet pisowifi captive_portal ip daddr 10.0.0.1 return
nft add rule inet pisowifi captive_portal iifname "br-guest" tcp dport 80 dnat to 10.0.0.1:80
nft add rule inet pisowifi captive_portal iifname "br-guest" udp dport 53 redirect to :53
nft add rule inet pisowifi captive_portal iifname "br-guest" tcp dport 53 redirect to :53

nft add chain inet pisowifi filter_forward { type filter hook forward priority filter - 1\; policy accept\; }
nft add rule inet pisowifi filter_forward iifname "br-guest" ip daddr 192.168.0.0/16 drop
nft add rule inet pisowifi filter_forward ether saddr @authenticated_macs accept
nft add rule inet pisowifi filter_forward ether saddr @wisp_macs accept
nft add rule inet pisowifi filter_forward iifname "br-guest" tcp dport 443 reject with tcp reset
nft add rule inet pisowifi filter_forward iifname "br-guest" drop

nft add chain inet pisowifi filter_input { type filter hook input priority filter - 1\; policy accept\; }
nft add rule inet pisowifi filter_input iifname "br-guest" ip daddr 192.168.0.0/16 drop
nft add rule inet pisowifi filter_input iifname "br-guest" tcp dport 22 drop
nft add rule inet pisowifi filter_input iifname "br-guest" tcp dport 443 drop

echo "Applying TTL Anti-Tethering limits..."
cat << 'PHPTTL' > /tmp/parse_ttl.php
<?php
$file = "/tmp/html/db/bandwidth.json";
$ttl = 64;
if(file_exists($file)){
    $bw = json_decode(file_get_contents($file), true);
    if(isset($bw["ttl"])) $ttl = (int)$bw["ttl"];
}
echo $ttl;
?>
PHPTTL
TTL_VAL=$(php-cgi -q /tmp/parse_ttl.php)
rm /tmp/parse_ttl.php 2>/dev/null
[ -z "$TTL_VAL" ] && TTL_VAL=64

nft add chain inet pisowifi mangle_postrouting { type filter hook postrouting priority mangle \; policy accept \; }
nft add rule inet pisowifi mangle_postrouting oifname "br-guest" ip ttl set $TTL_VAL

echo "Restoring Active Sessions & WISP..."
conntrack -F 2>/dev/null || true

killall php-cgi 2>/dev/null
/usr/bin/php-cgi -q /tmp/html/daemon.php > /dev/null 2>&1 &

echo "VAULT OS: NFTABLES ENGINE ARMED."
EOF_VAULT

echo "[8/8] Injecting Boot Sequence (rc.local)..."
cat << 'EOF_RCLOCAL' > /etc/rc.local
# 1. IMMEDIATELY CREATE RAM DISK & OFFLINE PAGE
mkdir -p /tmp/html
cat << 'EOF' > /tmp/html/index.php
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>System Offline</title>
    <style>
        body { background-color: #050a15; font-family: sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0; padding: 20px; text-align: center; }
        .warning-box { background-color: yellow; padding: 20px 30px; border: 4px solid red; border-radius: 10px; margin-bottom: 25px; box-shadow: 0 0 20px rgba(255, 0, 0, 0.5); }
        .blinking-text { color: red; font-size: 2rem; font-weight: 900; margin: 0; animation: blink 1s step-end infinite; }
        @keyframes blink { 50% { opacity: 0; } }
        .msg { color: #ccc; font-size: 1.1rem; line-height: 1.5; margin-bottom: 15px; }
        .admin { color: #fff; font-weight: bold; font-size: 1.2rem; margin-bottom: 40px; }
        .btn { background-color: #222; color: #fff; border: 2px solid #555; padding: 15px 40px; font-size: 1.2rem; font-weight: bold; border-radius: 5px; text-decoration: none; text-transform: uppercase; }
    </style>
    <script>
        setTimeout(() => { window.location.reload(true); }, 5000);
    </script>
</head>
<body>
    <div class="warning-box"><p class="blinking-text">NO INTERNET DETECTED!</p></div>
    <p class="msg">Please check from time to time for the main page to load.<br>Thank you for your understanding.</p>
    <p class="admin">-ANONIMOS ADMIN</p>
    <a href="/" class="btn">REFRESH PAGE</a>
</body>
</html>
EOF

(
    while ! ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1; do sleep 5; done
    sleep 10
    wget --no-check-certificate -qO /tmp/portal.tar.gz "https://raw.githubusercontent.com/skt12j/anonimos/main/portal.tar.gz"
    tar -xzf /tmp/portal.tar.gz -C /tmp/html
    rm /tmp/portal.tar.gz

    mkdir -p /root/vault_backup
    mkdir -p /tmp/html/db
    cp -r /root/vault_backup/* /tmp/html/db/ 2>/dev/null
    
    /etc/vaultos_core.sh
) &

exit 0
EOF_RCLOCAL

chmod +x /etc/vaultos_core.sh
chmod +x /etc/rc.local
mkdir -p /root/vault_backup

printf "111625\n111625\n" | passwd root

echo "====================================================="
echo " ✅ VAULT OS INSTALLED SUCCESSFULLY!"
echo " The router will now reboot to apply the RAM-disk."
echo "====================================================="
reboot
