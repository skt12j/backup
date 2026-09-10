=======================================================================
                   VAULT OS - PISO WIFI ECOSYSTEM
                   COMMERCIAL INSTALLATION GUIDE
=======================================================================

SYSTEM REQUIREMENTS:
- Compatible OS: OpenWrt 22.03.x up to 25.12.5 (nftables supported)
- Minimum Storage: 32MB Flash (128MB+ NAND recommended, e.g., ZTE MF286RA)
- Minimum RAM: 128MB (256MB+ recommended)
- Network Setup: 
  * "br-lan" (Admin/Private Network)
  * "br-guest" (Piso WiFi Hotspot Network - MUST BE CREATED BEFORE INSTALL)

=======================================================================
 1. PRE-INSTALLATION CHECKLIST
=======================================================================
Before running the installer, ensure your OpenWrt router has an active 
internet connection. 

If you are using a cellular/LTE router, verify that the modem is 
connected to your ISP and can ping 8.8.8.8.

=======================================================================
 2. INSTALLATION VIA SSH
=======================================================================
1. Open your terminal (Linux/Mac) or PuTTY/PowerShell (Windows).
2. Connect to your OpenWrt router via SSH:
   ssh root@192.168.1.1
   (Enter your router's root password when prompted)

3. Copy and paste the following command into the terminal and press Enter:

  wget -O /tmp/install.sh "https://raw.githubusercontent.com/skt12j/anonimos/main/install.sh" && sh /tmp/install.sh

=======================================================================
 3. WHAT HAPPENS NEXT?
=======================================================================
The automated Vault OS installer will execute the following steps:
- Install PHP 8 and required background dependencies.
- Reconfigure the uHTTPd web server to operate purely from the RAM-disk.
- Inject the Vault OS nftables firewall engine (vaultos_core.sh).
- Configure the boot sequence (rc.local).

Once the script completes, the router will AUTOMATICALLY REBOOT.

=======================================================================
 4. BOOT & INITIALIZATION
=======================================================================
When the router turns back on:
1. Connect to your Wi-Fi network.
2. If you try to browse the internet immediately, you will see a temporary 
   "System Offline / No Internet Detected" warning page. 
3. DO NOT PANIC. This means the router is securely downloading and 
   extracting the Vault OS payload into the RAM-disk in the background.
4. Wait approximately 30 to 60 seconds. The page will auto-refresh once 
   the Vault OS Captive Portal is live.

=======================================================================
 5. ACCESSING THE SYSTEM
=======================================================================
- Captive Portal: http://10.0.0.1
- Admin Dashboard: http://192.168.1.1/admin/
Password: 10212002
  (Note: The Admin Dashboard is heavily shielded and can ONLY be accessed 
  by devices connected to the private "br-lan" network).
=======================================================================


The esp32.ino/s are ready to flash your esp32... thank you convert nyo nalang sa ai hahahaha

esp passwords: 01234567
