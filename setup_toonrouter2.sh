#!/bin/sh
# Setup ToonRouter2 WiFi script
# This script configures the Toon to connect to ToonRouter2 WiFi with internet pass-through

# Display script info
echo "Setting up ToonRouter2 WiFi connection..."
echo "This script will configure your Toon to connect to ToonRouter2 WiFi network"
echo "NOTE: This script should be run on the Toon device, not on your PC!"

# Detect environment
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" = "kali" ]; then
        echo "ERROR: This script should be copied to and run on the Toon device, not on Kali Linux."
        echo "Please copy this script to your USB stick and run it on the Toon."
        exit 1
    fi
fi

# Stop networking services
echo "Stopping networking services..."
if [ -f /etc/init.d/networking ]; then
    /etc/init.d/networking stop >/dev/null 2>&1
fi
killall wpa_supplicant >/dev/null 2>&1
killall udhcpc >/dev/null 2>&1
killall dhclient >/dev/null 2>&1

# Create wpa_supplicant configuration
echo "Creating WiFi configuration..."
cat > /etc/wpa_supplicant.conf << EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1

network={
    ssid="TounRouter2"
    scan_ssid=1
    key_mgmt=NONE
    priority=10
}
EOF

# Create network interfaces configuration
echo "Configuring network interfaces..."
cat > /etc/network/interfaces << EOF
# Loopback interface
auto lo
iface lo inet loopback

# Primary interface - WiFi
auto wlan0
iface wlan0 inet dhcp
    wpa-conf /etc/wpa_supplicant.conf
EOF

# Setup DNS configuration
echo "Setting up DNS configuration..."
cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# Start networking
echo "Starting WiFi connection..."
ifconfig wlan0 up 2>/dev/null || ip link set wlan0 up 2>/dev/null
sleep 2

# Start wpa_supplicant more safely
echo "Starting wpa_supplicant..."
wpa_supplicant -B -Dwext -iwlan0 -c/etc/wpa_supplicant.conf || wpa_supplicant -B -Dnl80211 -iwlan0 -c/etc/wpa_supplicant.conf

sleep 3

# Try different DHCP clients (Toon has udhcpc, some systems have dhclient)
echo "Requesting DHCP address..."
if command -v udhcpc >/dev/null 2>&1; then
    udhcpc -i wlan0 -b
elif command -v dhclient >/dev/null 2>&1; then
    dhclient wlan0
else
    echo "No DHCP client found. Please manually run dhcp client for wlan0"
fi

# Test internet connection
echo "Testing internet connection..."
ping -c 1 8.8.8.8 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Success! ToonRouter2 WiFi is connected and internet is accessible."
    echo "Your Toon is now connected to TounRouter2 WiFi network."
else
    echo "Warning: Internet connection test failed."
    echo "The Toon is configured for TounRouter2 WiFi, but internet access might not be working."
    echo "Try running these commands manually on the Toon:"
    echo "  wpa_supplicant -B -Dwext -iwlan0 -c/etc/wpa_supplicant.conf"
    echo "  udhcpc -i wlan0"
fi

# Make configuration persistent across reboots
echo "Making configuration persistent..."
mkdir -p /mnt/data/tsc/network 2>/dev/null || mkdir -p /tmp/network
if [ -d /mnt/data/tsc/network ]; then
    # We're on a Toon
    cp /etc/wpa_supplicant.conf /mnt/data/tsc/network/
    cp /etc/network/interfaces /mnt/data/tsc/network/
    cp /etc/resolv.conf /mnt/data/tsc/network/

    # Create a startup script to restore the configuration after reboot
    cat > /etc/rc5.d/S39toonrouter2.sh << EOF
#!/bin/sh
if [ -f /mnt/data/tsc/network/wpa_supplicant.conf ]; then
    cp /mnt/data/tsc/network/wpa_supplicant.conf /etc/
    cp /mnt/data/tsc/network/interfaces /etc/network/
    cp /mnt/data/tsc/network/resolv.conf /etc/
fi
EOF
    chmod +x /etc/rc5.d/S39toonrouter2.sh
    echo "Configuration will persist across reboots."
else
    # Not on a Toon, just store in /tmp
    cp /etc/wpa_supplicant.conf /tmp/network/
    cp /etc/network/interfaces /tmp/network/
    cp /etc/resolv.conf /tmp/network/
    echo "Notice: Not running on a Toon. Configuration saved to /tmp/network/"
fi

echo "Setup completed!
"
echo "==================================================================="
echo "IMPORTANT: This script is designed to be run ON THE TOON device."
echo "If you're running it on Kali, it's preparing files for the Toon."
echo "Copy the /tmp/network files to the Toon's /etc directory manually."
echo "===================================================================" 