#!/bin/sh
# Setup ToonRouter2 WiFi script
# This script configures the Toon to connect to ToonRouter2 WiFi with internet pass-through

# Display script info
echo "Setting up ToonRouter2 WiFi connection..."
echo "This script will configure your Toon to connect to ToonRouter2 WiFi network"

# Stop networking services
echo "Stopping networking services..."
/etc/init.d/networking stop >/dev/null 2>&1
killall wpa_supplicant >/dev/null 2>&1
killall udhcpc >/dev/null 2>&1

# Create wpa_supplicant configuration
echo "Creating WiFi configuration..."
cat > /etc/wpa_supplicant.conf << EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1

network={
    ssid="TounRouter2"
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
ifup wlan0
wpa_supplicant -B -Dwext -iwlan0 -c/etc/wpa_supplicant.conf
sleep 3
udhcpc -i wlan0 -b

# Test internet connection
echo "Testing internet connection..."
ping -c 1 8.8.8.8 >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Success! ToonRouter2 WiFi is connected and internet is accessible."
    echo "Your Toon is now connected to TounRouter2 WiFi network."
else
    echo "Warning: Internet connection test failed."
    echo "The Toon is configured for TounRouter2 WiFi, but internet access might not be working."
fi

# Make configuration persistent across reboots
echo "Making configuration persistent..."
mkdir -p /mnt/data/tsc/network
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

echo "Setup completed!" 