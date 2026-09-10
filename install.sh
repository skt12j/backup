#!/bin/sh
# ===================================================================
# ANONIMO'S VAULT OS - ONE-CLICK INSTALLER
# ===================================================================

echo "====================================================="
echo "  INITIALIZING VAULT OS INSTALLATION..."
echo "====================================================="

echo "[1/5] Updating OpenWrt packages and installing PHP..."
opkg update
opkg install php8 php8-cgi php8-mod-session php8-mod-json curl wget-ssl tar conntrack

echo "[2/5] Configuring uHTTPd Web Server for RAM-Disk..."
uci set uhttpd.main.home='/tmp/html'
uci set uhttpd.main.index_page='index.php'
uci set uhttpd.main.error_page='/index.php'
uci add_list uhttpd.main.interpreter='.php=/usr/bin/php-cgi'
uci commit uhttpd

echo "[3/5] Writing Firewall Engine (vaultos_core.sh)..."
cat << 'EOF_VAULT' > /etc/vaultos_core.sh
#!/bin/sh
# ANONIMO'S VAULT OS - OPENWRT NFTABLES CORE

echo "Vault OS initializing..."

# 🔥 FIX 1: GRANT WEB SERVER PERMISSION TO CONTROL FIREWALL 🔥
chmod +s /usr/sbin/nft 2>/dev/null
chmod +s /usr/sbin/conntrack 2>/dev/null

# 1. Flush old nftables rules
nft delete table inet pisowifi 2>/dev/null

# 2. Create the Piso WiFi Table and MAC Sets
nft add table inet pisowifi
nft add set inet pisowifi authenticated_macs { type ether_addr\; }
nft add set inet pisowifi wisp_macs { type ether_addr\; }

# 3. Captive Portal Redirection (NAT)
nft add chain inet pisowifi captive_portal { type nat hook prerouting priority dstnat - 1\; policy accept\; }

nft add rule inet pisowifi captive_portal ether saddr @authenticated_macs return
nft add rule inet pisowifi captive_portal ether saddr @wisp_macs return
nft add rule inet pisowifi captive_portal ip daddr 10.0.0.1 return
nft add rule inet pisowifi captive_portal iifname "br-guest" tcp dport 80 redirect to :80
nft add rule inet pisowifi captive_portal iifname "br-guest" udp dport 53 redirect to :53
nft add rule inet pisowifi captive_portal iifname "br-guest" tcp dport 53 redirect to :53

# 4. Internet Blocking (Forwarding)
nft add chain inet pisowifi filter_forward { type filter hook forward priority filter - 1\; policy accept\; }

# 🛑 THE MODEM PROTECTOR 🛑
nft add rule inet pisowifi filter_forward iifname "br-guest" ip daddr 192.168.1.1 drop
nft add rule inet pisowifi filter_forward iifname "br-guest" ip daddr 192.168.254.254 drop

nft add rule inet pisowifi filter_forward ether saddr @authenticated_macs accept
nft add rule inet pisowifi filter_forward ether saddr @wisp_macs accept
nft add rule inet pisowifi filter_forward iifname "br-guest" tcp dport 443 reject with tcp reset
nft add rule inet pisowifi filter_forward iifname "br-guest" drop

# 🛑 THE ROUTER PROTECTOR (INPUT CHAIN) 🛑
nft add chain inet pisowifi filter_input { type filter hook input priority filter - 1\; policy accept\; }
nft add rule inet pisowifi filter_input iifname "br-guest" tcp dport 22 drop
nft add rule inet pisowifi filter_input iifname "br-guest" tcp dport 443 drop

# 5. Network Anti-Tethering (TTL)
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

# 6. Restore WISP Subscribers
echo "Restoring WISP Subscribers..."
cat << 'PHPWISP' > /tmp/parse_wisp.php
<?php
$file = "/tmp/html/db/subscriptions.json";
if(file_exists($file)){
    $subs = json_decode(file_get_contents($file), true);
    if($subs){
        foreach($subs as $id => $s){
            if(isset($s["status"]) && $s["status"] === "active") {
                foreach($s["macs"] as $mac) {
                    if (!empty($mac)) echo strtolower(trim($mac))."\n";
                }
            }
        }
    }
}
?>
PHPWISP
php-cgi -q /tmp/parse_wisp.php | grep -iE "^([0-9a-f]{2}:){5}[0-9a-f]{2}$" > /tmp/active_subs.txt

while read -r MAC; do
    if [ -n "$MAC" ]; then
        nft add element inet pisowifi wisp_macs { $MAC } 2>/dev/null
    fi
done < /tmp/active_subs.txt

# 7. Restore Active Piso WiFi Sessions
echo "Restoring Active Piso WiFi Sessions..."
cat << 'PHPSESS' > /tmp/parse_sess.php
<?php
$file = "/tmp/html/db/sessions.json";
if(file_exists($file)){
    $sessions = json_decode(file_get_contents($file), true);
    if($sessions){
        foreach($sessions as $mac => $s){
            if(isset($s["status"]) && $s["status"] === "active") {
                echo strtolower(trim($mac))."\n";
            }
        }
    }
}
?>
PHPSESS
php-cgi -q /tmp/parse_sess.php | grep -iE "^([0-9a-f]{2}:){5}[0-9a-f]{2}$" > /tmp/active_sessions.txt

while read -r S_MAC; do
    if [ -n "$S_MAC" ]; then
        nft add element inet pisowifi authenticated_macs { $S_MAC } 2>/dev/null
    fi
done < /tmp/active_sessions.txt

rm /tmp/parse_wisp.php /tmp/parse_sess.php /tmp/active_subs.txt /tmp/active_sessions.txt 2>/dev/null

# 8. Clear Conntrack
conntrack -F 2>/dev/null || true

# 9. Start the Master Daemon
killall php-cgi 2>/dev/null
/usr/bin/php-cgi -q /tmp/html/daemon.php > /dev/null 2>&1 &

echo "VAULT OS: NFTABLES ENGINE ARMED."
EOF_VAULT

echo "[4/5] Injecting Boot Sequence (rc.local)..."
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
        // Auto-refresh every 5 seconds to check if Vault OS has finished downloading
        setTimeout(() => { window.location.reload(true); }, 5000);
    </script>
</head>
<body>
    <div class="warning-box">
        <p class="blinking-text">NO INTERNET DETECTED!</p>
    </div>
    
    <p class="msg">Please check from time to time for the main page to load.<br>Thank you for your understanding.</p>
    <p class="admin">-ANONIMOS ADMIN</p>
    
    <a href="/" class="btn">REFRESH PAGE</a>
</body>
</html>
EOF

# 2. RUN DOWNLOAD ENGINE IN BACKGROUND (So router finishes booting)
(
    # Wait for raw internet (bypasses DNS issues)
    while ! ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1; do sleep 5; done
    
    # Wait 10 seconds for the router to sync its clock to the present year
    sleep 10
    
    # Internet found! Download Vault OS and extract it OVER the offline page
    wget --no-check-certificate -qO /tmp/portal.tar.gz "https://raw.githubusercontent.com/skt12j/anonimos/main/portal.tar.gz"
    tar -xzf /tmp/portal.tar.gz -C /tmp/html
    rm /tmp/portal.tar.gz

    # 🔥 ANTI-BROWNOUT VAULT RESTORE 🔥
    # Copy the permanent backup back into the RAM disk before starting the firewall!
    mkdir -p /root/vault_backup
    mkdir -p /tmp/html/db
    cp -r /root/vault_backup/* /tmp/html/db/ 2>/dev/null
    
    # Start the Vault OS Firewall Engine
    /etc/vaultos_core.sh
) &

exit 0
EOF_RCLOCAL

echo "[5/5] Securing Permissions and Initializing..."
chmod +x /etc/vaultos_core.sh
chmod +x /etc/rc.local
mkdir -p /root/vault_backup

echo "====================================================="
echo " ✅ VAULT OS INSTALLED SUCCESSFULLY!"
echo " The router will now reboot to apply the RAM-disk."
echo "====================================================="
reboot
