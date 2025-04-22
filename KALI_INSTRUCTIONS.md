# Toon Rooting Instructies voor Kali Linux

Dit document bevat stap-voor-stap instructies voor het rooten van je Toon op Kali Linux.

## Voorbereiding

1. Start je laptop op vanaf een Kali Linux USB stick
2. Zorg dat je WiFi werkt in Kali Linux
3. Open een terminal

## Stappen voor het rooten

### 1. Controleer of je tools geïnstalleerd zijn

Voer de volgende commando's uit om te controleren of alle benodigde tools aanwezig zijn:

```bash
which nc curl tcpdump grep sed iptables ip mkfifo
```

Als er tools ontbreken, installeer ze dan met:

```bash
sudo apt update && sudo apt install -y netcat-traditional curl tcpdump grep sed iptables iproute2 coreutils
```

### 2. Zet de WiFi-hotspot op

```bash
cd Root-A-Toon-USB-Stick
sudo bash setup-wifi.sh
```

Als je WiFi-hardware niet wordt herkend, kun je het interface handmatig opgeven:

```bash
sudo bash setup-wifi.sh wlan0  # Vervang wlan0 door je WiFi interface naam
```

### 3. Verbind je Toon met de WiFi

- Zoek op je Toon naar het WiFi-netwerk "ToonRouter"
- Verbind je Toon met dit netwerk
- Wacht tot de Toon is verbonden

### 4. Voor niet-geactiveerde Toons

Als je Toon nog niet geactiveerd is, voer dan eerst uit:

```bash
sudo bash activate-toon.sh
```

Volg de instructies op het scherm.

### 5. Root je Toon

```bash
sudo bash root-toon.sh root
```

Volg de instructies op het scherm. Je moet mogelijk:
- Op de Toon naar instellingen -> software gaan
- Wachten tot het script de verbinding detecteert
- Het IP-adres van je Toon handmatig opgeven als het niet automatisch wordt gevonden

## Problemen oplossen

### De WiFi-hotspot werkt niet

Als je problemen hebt met het opzetten van de WiFi-hotspot, probeer dan:

```bash
# Toon beschikbare interfaces
ip -br link show

# Kies een interface en gebruik deze expliciet
sudo bash setup-wifi.sh jouw_interface_naam
```

### Payload wordt niet gedownload

Het script slaat nu automatisch een lokale kopie van de payload op. Als er problemen zijn met het downloaden van de payload, wordt een ingebouwde minimale payload gebruikt.

### Toon niet gevonden

Als het script je Toon niet kan vinden, gebruik dan een van deze methoden:

1. Verbind je Toon via WiFi en vind het IP-adres in je router
2. Laat het script het netwerk scannen en selecteer je Toon uit de lijst
3. Probeer het netcat commando direct:
   ```bash
   nc -l -p 31080
   ```

### SSH verbinding werkt niet na rooten

Wacht ongeveer een minuut na het rooten en probeer dan:

```bash
ssh root@TOON_IP
```

Gebruik als wachtwoord: `toon`

## Tips

- Zorg dat je laptop is opgeladen of aangesloten op stroom
- Blijf in de buurt van je Toon voor een goed WiFi-signaal
- Als het process vastloopt, reboot zowel je Toon als je laptop en probeer opnieuw

## Nadat je Toon is geroot

Na het rooten kun je:
- SSH'en naar je Toon: `ssh root@TOON_IP` (wachtwoord: `toon`)
- De ToonStore installeren voor meer apps
- Aangepaste widgets installeren
- Automatisering toevoegen 