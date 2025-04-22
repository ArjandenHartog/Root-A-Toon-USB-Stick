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

/sbin/iptables -F FORWARD

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
/sbin/iptables -I FORWARD -p tcp --dport 443 -j DROP

# Run tcpdump and handle possible errors
TCPDUMP_OUTPUT=""
echo "Starting tcpdump to listen for Toon connections..."
for i in {1..5}; do
  TCPDUMP_OUTPUT=$(/usr/bin/tcpdump -n -i any port 31080 -c 1 2>/dev/null)
  if [ $? -eq 0 ] && [ ! -z "$TCPDUMP_OUTPUT" ]; then
    break
  fi
  echo "Retrying tcpdump ($i/5)..."
  sleep 3
done

if [ -z "$TCPDUMP_OUTPUT" ]; then
  echo "ERROR: tcpdump failed to capture any traffic from Toon."
  echo "Make sure your Toon is correctly connected to your WiFi network."
  echo "Check if tcpdump is installed with 'which tcpdump'."
  exit 1
fi

IP=`echo $TCPDUMP_OUTPUT | cut -d\  -f7 | cut -d\. -f1,2,3,4`

echo ""
echo "The Toon is connecting to IP: $IP"

echo ""
echo "Try to activate."

/sbin/ip addr add $IP/32 dev lo 2>/dev/null

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

while ! $DONE 
do
echo "Waiting for activation request..."

if [ "$USING_NC_Q" = true ]; then
  echo "Using netcat with -q option"
  cat /tmp/pipe.out | nc -l -p 31080 -q 0 | tee /tmp/pipe.in &
else
  echo "Using netcat without -q option"
  cat /tmp/pipe.out | (nc -l -p 31080 || true) | tee /tmp/pipe.in &
fi

NC_PID=$!
echo "Netcat PID: $NC_PID"

while read line
do
echo "Received: $line"
if [[ $line = *"action class"* ]]
then
  echo "Found action class line"
  COMMONNAME=`echo $line | sed 's/.* commonname="\(.*\)".*/\1/'`
  UUID="$COMMONNAME:happ_scsync" 
  REQUESTID=`echo $line | sed 's/.* requestid="\(.*\)" .*/\1/'`
  TOSEND=`echo $RESPONSE | sed "s/_REQUESTID_/$REQUESTID/" | sed "s/_DESTCOMMONNAME_/$COMMONNAME/" | sed "s/_DESTUUID_/$UUID/" `
fi
if [[ $line = *"<u:getInformation"* ]]
then
  echo "Ok sending the response for the activation request"
  echo -e $TOSEND > /tmp/pipe.out
  DONE=true
elif [[ $line = *"token"* ]]
then
  echo "This is not an activation request."
  echo "" > /tmp/pipe.out
fi
  
done < /tmp/pipe.in

if [ "$DONE" = false ]; then
  echo "No valid activation request received. Waiting for another connection..."
  kill $NC_PID 2>/dev/null
  sleep 1
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

while ! $DONE 
do
echo "Waiting for registration confirmation request..."

if [ "$USING_NC_Q" = true ]; then
  echo "Using netcat with -q option"
  cat /tmp/pipe.out | nc -l -p 31080 -q 0 | tee /tmp/pipe.in &
else
  echo "Using netcat without -q option"
  cat /tmp/pipe.out | (nc -l -p 31080 || true) | tee /tmp/pipe.in &
fi

NC_PID=$!
echo "Netcat PID: $NC_PID"

while read line
do
echo "Received: $line"
if [[ $line = *"action class"* ]]
then
  echo "Found action class line"
  COMMONNAME=`echo $line | sed 's/.* commonname="\(.*\)".*/\1/'`
  UUID="$COMMONNAME:happ_scsync" 
  REQUESTID=`echo $line | sed 's/.* requestid="\(.*\)" .*/\1/'`
  TOSEND=`echo $RESPONSE | sed "s/_REQUESTID_/$REQUESTID/" | sed "s/_DESTCOMMONNAME_/$COMMONNAME/" | sed "s/_DESTUUID_/$UUID/" `
fi
if [[ $line = *"<u:RegisterQuby"* ]]
then
  echo "Ok sending the response for the activation confirm request"
  echo -e $TOSEND > /tmp/pipe.out
  DONE=true
fi
  
done < /tmp/pipe.in

if [ "$DONE" = false ]; then
  echo "No valid registration request received. Waiting for another connection..."
  kill $NC_PID 2>/dev/null
  sleep 1
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
ip addr del $IP/32 dev lo 2>/dev/null
rm -f /tmp/pipe.in
rm -f /tmp/pipe.out
/sbin/iptables -D FORWARD -p tcp --dport 443 -j DROP 2>/dev/null
