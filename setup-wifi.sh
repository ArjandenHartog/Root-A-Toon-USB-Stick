#!/bin/bash

clear

if [[ $EUID -ne 0 ]]
then
  echo ""
  echo " This script can be used to share your Internet over Wi-Fi."
  echo ""
  echo "    Usage :"
  echo ""
  echo "     share without a password : (easier to connect Toon 8=) )"
  echo ""
  echo "       sudo bash $0"
  echo ""
  echo "     share with a password    : (at least 8 characters and safer 8=) )"
  echo ""
  echo "       sudo bash $0 password"
  echo ""
  echo "     share with specific interface :"
  echo ""
  echo "       sudo bash $0 [password] interface_name"
  echo ""
  echo " The name of the Wi-Fi to connect to will be ToonRouter."
  echo ""
  exit 0
fi

# Check if we have NetworkManager installed
if ! command -v nmcli &> /dev/null; then
  echo "ERROR: NetworkManager (nmcli) is not installed."
  echo "Please install NetworkManager with: sudo apt-get install network-manager"
  exit 1
fi

# Display all available network interfaces
echo "Available network interfaces:"
ip link show | grep -E ": [a-zA-Z0-9]+:" | sed -E 's/^[0-9]+: ([a-zA-Z0-9]+):.*/\1/' | while read -r interface; do
  echo " - $interface ($(ip -br link show $interface | awk '{print $2}'))"
done
echo ""

# Determine if we have a manually specified interface
MANUAL_INTERFACE=""
if [[ "$2" != "" ]]; then
  MANUAL_INTERFACE="$2"
  echo "Using manually specified interface: $MANUAL_INTERFACE"
elif [[ "$1" != "" && "$1" != password* && "$1" != pass* && ${#1} -gt 2 ]]; then
  MANUAL_INTERFACE="$1"
  Password=""
  echo "Using manually specified interface: $MANUAL_INTERFACE"
fi

# Find WiFi interface if not manually specified
if [[ "$MANUAL_INTERFACE" == "" ]]; then
  # First try using nmcli
  WIFI_INTERFACE=$(nmcli device status | grep wifi | awk '{print $1}' | head -n 1)
  
  # If nmcli didn't find anything, try other detection methods
  if [ -z "$WIFI_INTERFACE" ]; then
    # Try to find common wireless interface names
    for iface in wlan0 wlan1 wlp2s0 wlp3s0 wlp0s20f3; do
      if ip link show $iface &>/dev/null; then
        WIFI_INTERFACE=$iface
        break
      fi
    done
  fi
  
  # If still not found, check all interfaces
  if [ -z "$WIFI_INTERFACE" ]; then
    echo "No WiFi interface detected automatically."
    echo "Available interfaces:"
    
    # List all network interfaces (except lo)
    interfaces=$(ip -br link show | grep -v "lo" | awk '{print $1}')
    i=1
    declare -a iface_array
    
    for iface in $interfaces; do
      echo "$i: $iface"
      iface_array[$i]=$iface
      i=$((i+1))
    done
    
    echo ""
    echo "Please select an interface to use (enter number) or press Ctrl+C to cancel:"
    read selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -lt "$i" ]; then
      WIFI_INTERFACE=${iface_array[$selection]}
    else
      echo "Invalid selection. Exiting."
      exit 1
    fi
  fi
else
  # Use manually specified interface
  WIFI_INTERFACE=$MANUAL_INTERFACE
  
  # Check if interface exists
  if ! ip link show $WIFI_INTERFACE &>/dev/null; then
    echo "ERROR: Specified interface '$WIFI_INTERFACE' does not exist."
    echo "Available interfaces:"
    ip -br link show | grep -v "lo"
    exit 1
  fi
fi

echo "Using network interface: $WIFI_INTERFACE"

# Check if interface is up
if ip link show $WIFI_INTERFACE | grep -q "state DOWN"; then
  echo "WARNING: Interface $WIFI_INTERFACE is DOWN. Attempting to bring it up..."
  ip link set $WIFI_INTERFACE up
  sleep 2
fi

Password=$1
if [[ "$MANUAL_INTERFACE" == "$1" ]]; then
  Password=""
fi

if (( ${#Password} > 0 && ${#Password} < 8 ))
then
  echo ""
  echo "ERROR: Password too short. WiFi password must be at least 8 characters."
  echo ""
  exit 0
fi

# Clean up any existing ToonRouter connection
echo "Removing any existing ToonRouter connection..."
nmcli connection delete ToonRouter > /dev/null 2>&1

# Create the WiFi hotspot
echo "Setting up WiFi hotspot..."
if [ "$Password" == "" ] 
then
  echo ""
  echo "Creating open (unsecured) WiFi network named ToonRouter..."
  nmcli connection add type wifi ifname "$WIFI_INTERFACE" con-name ToonRouter autoconnect yes ssid ToonRouter mode ap 802-11-wireless.mode ap ipv4.method shared
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create WiFi hotspot."
    echo "Trying alternative method for virtual machines or non-standard setups..."
    # Alternative method using iptables and a direct connection
    echo "Setting up network forwarding and NAT..."
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Set up NAT
    iptables -t nat -A POSTROUTING -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
    iptables -A FORWARD -i "$WIFI_INTERFACE" -j ACCEPT
    
    echo "Network is now ready for direct connection."
    echo "Connect your Toon directly to this computer using an Ethernet cable."
    echo "Your Toon should receive an IP address via DHCP."
    exit 0
  fi
  echo ""
  echo "Note: No password is set on this network. Anyone can connect to it."
else
  echo ""
  echo "Creating password-protected WiFi network named ToonRouter..."
  nmcli connection add type wifi ifname "$WIFI_INTERFACE" con-name ToonRouter autoconnect yes ssid ToonRouter mode ap 802-11-wireless.mode ap ipv4.method shared 802-11-wireless-security.key-mgmt wpa-psk ipv4.method shared 802-11-wireless-security.psk "$Password"
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create WiFi hotspot."
    echo "Trying alternative method for virtual machines or non-standard setups..."
    # Alternative method using iptables and a direct connection
    echo "Setting up network forwarding and NAT..."
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Set up NAT
    iptables -t nat -A POSTROUTING -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
    iptables -A FORWARD -i "$WIFI_INTERFACE" -j ACCEPT
    
    echo "Network is now ready for direct connection."
    echo "Connect your Toon directly to this computer using an Ethernet cable."
    echo "Your Toon should receive an IP address via DHCP."
    exit 0
  fi
  echo ""
  echo "Note: Your WiFi password is: $Password"
fi

# Activate the connection
echo "Activating WiFi hotspot..."
nmcli connection up ToonRouter
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to activate WiFi hotspot."
  echo "Trying alternative method..."
  
  # Try to enable AP mode using iw if available
  if command -v iw &> /dev/null; then
    echo "Attempting to set up AP mode using iw..."
    iw dev $WIFI_INTERFACE set type __ap
    ip addr add 192.168.100.1/24 dev $WIFI_INTERFACE
    ip link set $WIFI_INTERFACE up
    
    # Start a simple DHCP server if available
    if command -v dnsmasq &> /dev/null; then
      echo "Starting DHCP server..."
      echo "interface=$WIFI_INTERFACE" > /tmp/dnsmasq.conf
      echo "dhcp-range=192.168.100.50,192.168.100.150,12h" >> /tmp/dnsmasq.conf
      dnsmasq -C /tmp/dnsmasq.conf
    else
      echo "DHCP server (dnsmasq) not available."
      echo "Your Toon will need to be configured with a static IP in the 192.168.100.x range."
    fi
    
    echo "Setting up network forwarding and NAT..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    iptables -t nat -A POSTROUTING -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE
    
    echo "Alternative WiFi setup complete. SSID: ToonRouter"
  else
    echo "iw tool not available. Cannot set up alternative WiFi AP."
    echo "Please connect your Toon directly to this computer using an Ethernet cable."
  fi
fi

# Display network information
echo ""
echo "WiFi hotspot 'ToonRouter' is now active!"
echo ""
echo "Network details:"
echo "  SSID: ToonRouter"
if [ "$Password" != "" ]; then
  echo "  Password: $Password"
else
  echo "  Password: [none - open network]"
fi
echo "  IP address: $(hostname -I | awk '{print $1}')"
echo ""
echo "You should now be able to connect your Toon to the WiFi network 'ToonRouter'."
echo ""
echo "If you don't see the ToonRouter SSID on your Toon:"
echo " - It may take some time for the network to appear"
echo " - Try turning WiFi off and on again on your Toon"
echo " - Make sure your computer's WiFi hardware is working properly"
echo " - If using a VM, make sure the WiFi adapter is passed through to the VM"
echo ""
echo "After connecting your Toon to ToonRouter, you can proceed with:"
echo " - sudo bash activate-toon.sh (if your Toon needs activation)"
echo " - sudo bash root-toon.sh (to root your Toon)"
echo ""
