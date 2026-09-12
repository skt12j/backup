=======================================================================
               VAULT OS - PISO WIFI & WISP ECOSYSTEM
             COMMERCIAL-GRADE SECURE DEPLOYMENT GUIDE
=======================================================================

SYSTEM REQUIREMENTS:
- Compatible Hardware: TP-Link Archer AX23 and dual-band OpenWrt routers
- Compatible OS: OpenWrt 22.03.x up to 25.x (nftables / Firewall4 supported)
- Storage: Minimum 32MB Flash
- RAM: Minimum 128MB (RAM-disk optimized via /tmp/html)

=======================================================================
 1. AUTOMATED DUAL-BAND WIFI CONFIGURATION
=======================================================================
Upon installation, Vault OS automatically scans your router's wireless chips 
and creates four dedicated interfaces:

- Private Admin LAN (Password Protected):
  * NIMOS MAIN 2.4G  (Password: 01234567)
  * NIMOS MAIN 5G    (Password: 01234567)

- Piso WiFi Hotspot (Open Captive Portal):
  * ANONIMO'S PISO WIFI 2.4G  (Open / No Password)
  * ANONIMO'S PISO WIFI 5G    (Open / No Password)

=======================================================================
 2. ONE-CLICK SSH INSTALLATION
=======================================================================
1. Connect to your OpenWrt router via SSH:
   ssh root@192.168.1.1 (enter your openwrt login password (root) or your default one

2. Copy, paste, and execute the following deployment command:

   wget -O /tmp/install.sh "https://raw.githubusercontent.com/skt12j/nimos/main/install.sh" && sh /tmp/install.sh

3. The installer will automatically:
   - Install PHP 8 packages and coreutils-base64.
   - Configure the uHTTPd web server to run directly out of the RAM-disk.
   - Auto-provision the dual-band SSIDs.
   - Write the hardened nftables core engine.
   - Automatically reboot the router.

=======================================================================
 3. HARDWARE-LOCKED ACTIVATION & LICENSING
=======================================================================
Vault OS utilizes node-locked security tied to your router's physical MAC.

1. After reboot, connect to either the Piso WiFi or LAN network.
2. Attempting to browse the internet will automatically redirect you to 
   the Hardware Activation page (`activate.php`).
3. The page will display your router's unique physical MAC address.
4. Send that MAC address to the administrator to receive your unique MD5 License Key.
5. Enter the key into the activation prompt. The system will securely save 
   the license, self-destruct the activation script to prevent tampering, 
   and unlock the full platform.

=======================================================================
 4. SYSTEM ACCESS REFERENCE
=======================================================================
- Captive Portal Gateway: http://10.0.0.1
- Admin Dashboard: http://192.168.1.1/admin/
  (Note: Protected by Subnet Shield; accessible exclusively via private LAN)
=======================================================================
