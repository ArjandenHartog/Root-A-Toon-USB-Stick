#!/bin/bash

if [[ $EUID -ne 0 ]]
then
 echo ""
 echo "    Usage :"
 echo ""
 echo "     sudo bash $0"
 echo ""
 exit 0
fi

# Ensure we have required tools
for cmd in nc curl tcpdump grep sed iptables ip mkfifo; do
  if ! command -v $cmd &> /dev/null; then
    echo "ERROR: Required command '$cmd' is not installed."
    echo "Please install it with: apt update && apt install -y $cmd"
    exit 1
  fi
done

# Check which netcat variant is available
if nc -h 2>&1 | grep -q "\-q"; then
  NC_COMMAND="nc -l -p"
  NC_COMMAND_EOF=" -q 0"
  USING_NC_Q=true
else
  NC_COMMAND="nc -l -p"
  NC_COMMAND_EOF=""
  USING_NC_Q=false
fi

echo "Using netcat command: $NC_COMMAND with EOF flag: $NC_COMMAND_EOF"

clear
echo ""
echo "Before you continue I assume your Internet is shared over Wi-Fi from this computer '$HOSTNAME'."
echo "You are sure that the sharing works, maybe connect your phone to that Wi-Fi to check."
echo "And that the root-toon.sh can not be used because your Toon was not activated yet."
echo "This script may contain more instructions in future, based on what we run into."
echo "I used it to activate 1 Toon 1, got a software update screen and put that in the instructions."
echo "That's why you see EITHER OR after you press [enter] to continue."
echo ""
read QUESTION

#cleanup earlier bad runs
rm -f /tmp/pipe.in
rm -f /tmp/pipe.out

killall -9 nc 2>/dev/null
killall -9 cat 2>/dev/null

# Safely clear firewall rules
echo "Cleaning up firewall rules..."
/sbin/iptables -D FORWARD -p tcp --dport 443 -j DROP 2>/dev/null || true

echo "-----------------------EITHER------------------------------------"
echo "First bring up your Toon and wait until it is in the activation screen."
echo "Connect to your Wi-Fi and wait until the service center is connected."
echo "and you are able to push the 'activate' button."
echo "Then, press the activate button on the Toon but don't give it a code yet."
echo "Then press [enter] to go on with this script."
echo ""
echo "--------------------------OR-------------------------------------"
echo "You do not get an activation screen but a software update screen."
echo "Press the buttons you need to continue to get the update."
echo "Downloading and installing takes a long time...."
echo "Be patient, after the installation your Toon will reboot."
echo "After reboot you see the 'Installatie Wizard' screen."
echo "Select 'Installeren'."
echo "Now you see the 'Welkom' screen."
echo "Select 'Activeren' in the narrow blue bar."
echo "Don't give in a code yet."
echo "Then press [enter] to go on with this script."
echo ""
read QUESTION
echo "Blocking all HTTPS (and therefore Toon VPN)."
echo "Now we wait until the Toon disconnects the VPN and sends traffic"
echo "towards the service center on the wifi."
echo "After a minute or maybe a bit more you can start the activation."
echo "Use a random activation code of 10 characters."
echo "In case it fails just retry until it succeeds."
echo "Don't go back to the home activation screen."
echo ""
echo "First wait until you see some messages below......."
echo ""

# Safely add iptables rule
echo "Adding firewall rule to block HTTPS..."
if ! /sbin/iptables -I FORWARD -p tcp --dport 443 -j DROP; then
  echo "WARNING: Failed to add iptables rule. Trying alternative method..."
  # Try with sudo explicitly
  sudo /sbin/iptables -I FORWARD -p tcp --dport 443 -j DROP || echo "ERROR: Could not add iptables rule. The script may not work correctly."
fi

# Run tcpdump and handle possible errors
echo "Starting tcpdump to listen for Toon connections..."
TCPDUMP_OUTPUT=""
MAX_ATTEMPTS=10
for i in $(seq 1 $MAX_ATTEMPTS); do
  echo "Listening attempt $i/$MAX_ATTEMPTS..."
  TCPDUMP_OUTPUT=$(/usr/bin/tcpdump -n -i any port 31080 -c 1 2>/dev/null || true)
  
  if [ ! -z "$TCPDUMP_OUTPUT" ]; then
    echo "Captured traffic from Toon!"
    break
  fi
  
  # If we're on attempt 5, try alternative method
  if [ $i -eq 5 ]; then
    echo "Having trouble capturing packets. Trying to find your network interfaces..."
    INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
    echo "Available interfaces: $INTERFACES"
    
    # Try each interface
    for iface in $INTERFACES; do
      echo "Trying interface $iface..."
      TCPDUMP_OUTPUT=$(/usr/bin/tcpdump -n -i $iface port 31080 -c 1 -v 2>/dev/null || true)
      if [ ! -z "$TCPDUMP_OUTPUT" ]; then
        echo "Success with interface $iface!"
        break 2
      fi
    done
  fi
  
  echo "No traffic detected, retrying in 3 seconds..."
  sleep 3
done

if [ -z "$TCPDUMP_OUTPUT" ]; then
  echo "ERROR: Failed to capture any traffic from Toon after $MAX_ATTEMPTS attempts."
  echo ""
  echo "Please manually enter the IP address of your Toon if you know it (or press Enter to exit):"
  read MANUAL_TOON_IP
  
  if [ -z "$MANUAL_TOON_IP" ]; then
    echo "Exiting. Please try again after checking your network connection."
    exit 1
  else
    echo "Using manually entered IP: $MANUAL_TOON_IP"
    # Use a dummy service center IP
    IP="1.2.3.4"
  fi
else
  IP=$(echo $TCPDUMP_OUTPUT | cut -d\  -f7 | cut -d\. -f1,2,3,4)
fi

echo ""
echo "The Toon is connecting to IP: $IP"

echo ""
echo "Try to activate."

# Add IP address to loopback safely
echo "Adding service center IP to loopback interface..."
if ! /sbin/ip addr add $IP/32 dev lo 2>/dev/null; then
  echo "WARNING: Failed to add IP address to loopback. Trying alternative method..."
  sudo /sbin/ip addr add $IP/32 dev lo 2>/dev/null || echo "ERROR: Could not add IP address. The script may not work correctly."
fi

# Create pipes if they don't exist
[ -f /tmp/pipe.in ] || /usr/bin/mkfifo /tmp/pipe.in
[ -f /tmp/pipe.out ] || /usr/bin/mkfifo /tmp/pipe.out

RESPONSE='HTTP/1.1 200 OK\n\n


<action xmlns:u="http://schema.homeautomationeurope.com/quby" class="response" uuid="0429a450-bd0c-11e0-962b-0800200c9a66" destuuid="_DESTUUID_" destcommonname="_DESTCOMMONNAME_" requestid="_REQUESTID_" serviceid="urn:hcb-hae-com:serviceId:quby">\n
  <u:getInformationForActivationCodeResponse>\n
    <Success>true</Success>\n
    <Reason>Success</Reason>\n
  </u:getInformationForActivationCodeResponse>\n
</action>\n
'

DONE=false
MAX_ATTEMPTS=5
ATTEMPT=1

while ! $DONE && [ $ATTEMPT -le $MAX_ATTEMPTS ]
do
echo "Attempt $ATTEMPT/$MAX_ATTEMPTS - Waiting for activation request..."

if [ "$USING_NC_Q" = true ]; then
  echo "Using netcat with -q option"
  cat /tmp/pipe.out | nc -l -p 31080 -q 0 | tee /tmp/pipe.in &
else
  echo "Using netcat without -q option"
  cat /tmp/pipe.out | (nc -l -p 31080 || true) | tee /tmp/pipe.in &
fi

NC_PID=$!
echo "Netcat PID: $NC_PID"

# Set a timeout for netcat
TIMEOUT=60
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
        echo "Found action class line"
        COMMONNAME=$(echo $line | sed 's/.* commonname="\(.*\)".*/\1/' || echo "unknown")
        UUID="$COMMONNAME:happ_scsync" 
        REQUESTID=$(echo $line | sed 's/.* requestid="\(.*\)" .*/\1/' || echo "unknown")
        TOSEND=$(echo $RESPONSE | sed "s/_REQUESTID_/$REQUESTID/" | sed "s/_DESTCOMMONNAME_/$COMMONNAME/" | sed "s/_DESTUUID_/$UUID/")
      fi
      
      if [[ $line = *"<u:getInformation"* ]]; then
        echo "Ok sending the response for the activation request"
        echo -e $TOSEND > /tmp/pipe.out
        DONE=true
        break
      elif [[ $line = *"token"* ]]; then
        echo "This is not an activation request."
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
  echo "No valid activation request received in attempt $ATTEMPT."
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
  else
    echo "Failed to receive a valid activation request after $MAX_ATTEMPTS attempts."
    echo "Please try again and make sure your Toon is properly connected to your WiFi."
    # Clean up
    ip addr del $IP/32 dev lo 2>/dev/null || true
    rm -f /tmp/pipe.in
    rm -f /tmp/pipe.out
    /sbin/iptables -D FORWARD -p tcp --dport 443 -j DROP 2>/dev/null || true
    exit 1
  fi
fi

done

echo "I received the activation request and sent back a response to allow the activation to proceed."
echo "Go on and accept the shown empty settings."

RESPONSE='HTTP/1.1 200 OK\n\n

<action xmlns:u="http://schema.homeautomationeurope.com/quby" class="response" uuid="0429a450-bd0c-11e0-962b-0800200c9a66" destuuid="_DESTUUID_" destcommonname="_DESTCOMMONUUID_" requestid="_REQUESTID_" serviceid="urn:hcb-hae-com:serviceId:quby">\n
  <u:RegisterQubyResponse>\n
    <StartDate>0</StartDate>\n
    <EndDate>-1</EndDate>\n
    <Status>IN_SUPPLY</Status>\n
    <ProductVariant>Toon</ProductVariant>\n
    <SoftwareUpdates>true</SoftwareUpdates>\n
    <ElectricityDisplay>false</ElectricityDisplay>\n
    <GasDisplay>false</GasDisplay>\n
    <HeatDisplay>false</HeatDisplay>\n
    <ProduDisplay>false</ProduDisplay>\n
    <ContentApps>false</ContentApps>\n
    <TelmiEnabled>false</TelmiEnabled>\n
    <HeatWinner>false</HeatWinner>\n
    <ElectricityOtherProvider>false</ElectricityOtherProvider>\n
    <GasOtherProvider>false</GasOtherProvider>\n
    <DistrictHeatOtherProvider>false</DistrictHeatOtherProvider>\n
    <CustomerName>TSC</CustomerName>\n
    <Success>true</Success>\n
    <Reason>Success</Reason>\n
    <ReasonDetails>Success</ReasonDetails>\n
  </u:RegisterQubyResponse>\n
</action>\n
'

DONE=false
ATTEMPT=1

while ! $DONE && [ $ATTEMPT -le $MAX_ATTEMPTS ]
do
echo "Attempt $ATTEMPT/$MAX_ATTEMPTS - Waiting for registration confirmation request..."

if [ "$USING_NC_Q" = true ]; then
  echo "Using netcat with -q option"
  cat /tmp/pipe.out | nc -l -p 31080 -q 0 | tee /tmp/pipe.in &
else
  echo "Using netcat without -q option"
  cat /tmp/pipe.out | (nc -l -p 31080 || true) | tee /tmp/pipe.in &
fi

NC_PID=$!
echo "Netcat PID: $NC_PID"

# Set a timeout for netcat
TIMEOUT=60
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
        echo "Found action class line"
        COMMONNAME=$(echo $line | sed 's/.* commonname="\(.*\)".*/\1/' || echo "unknown")
        UUID="$COMMONNAME:happ_scsync" 
        REQUESTID=$(echo $line | sed 's/.* requestid="\(.*\)" .*/\1/' || echo "unknown")
        TOSEND=$(echo $RESPONSE | sed "s/_REQUESTID_/$REQUESTID/" | sed "s/_DESTCOMMONNAME_/$COMMONNAME/" | sed "s/_DESTUUID_/$UUID/")
      fi
      
      if [[ $line = *"<u:RegisterQuby"* ]]; then
        echo "Ok sending the response for the activation confirm request"
        echo -e $TOSEND > /tmp/pipe.out
        DONE=true
        break
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
  echo "No valid registration request received in attempt $ATTEMPT."
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
  else
    echo "Failed to receive a valid registration request after $MAX_ATTEMPTS attempts."
    echo "Please continue with the next steps and if it doesn't work, try running the script again."
  fi
fi

done

echo ""
echo "And that is it! Almost that is...."
echo "We activated the toon."
echo "However in the main activation screen you can not proceed yet."
echo "Don't worry."
echo ""
echo "Just reboot your toon after 10 seconds by unplugging the power"
echo "and it will bring you back to the activation screen"
echo "or it will come back in the 'Installatie Wizard' screen."
echo ""
echo "When you see the activation screen press finish."
echo "When you see the 'Installatie Wizard' screen...."
echo " - Select 'Installeren'."
echo " - Now you see the 'Welkom' screen."
echo " - Select 'Klaar' in the top right corner."
echo ""
echo "See a message about 'Installeer Updates'"
echo "just wait for your Toon to restart"
echo ""
echo "After the reboot you see a 'Welkom' screen."
echo ""
echo "Press the big 'X' and you are ready for root-toon.sh "
echo ""

# Clean up
echo "Cleaning up..."
ip addr del $IP/32 dev lo 2>/dev/null || true
rm -f /tmp/pipe.in
rm -f /tmp/pipe.out
/sbin/iptables -D FORWARD -p tcp --dport 443 -j DROP 2>/dev/null || true
