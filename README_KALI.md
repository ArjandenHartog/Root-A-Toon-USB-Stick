# Root-A-Toon met Kali Linux USB Stick

Deze scripts stellen je in staat om een Toon te rooten vanaf een Kali Linux USB Stick.

## Snelstart instructies

Na het opstarten van je laptop met Kali Linux:

1. Open een terminal
2. Voer deze commando's uit:

```bash
git clone https://github.com/ToonSoftwareCollective/Root-A-Toon-USB-Stick.git
cd Root-A-Toon-USB-Stick
chmod +x *.sh
sudo bash setup-wifi.sh
```

3. Verbind je Toon met het WiFi-netwerk "ToonRouter"
4. Als je Toon nog niet geactiveerd is:

```bash
sudo bash activate-toon.sh
```

5. Root je Toon:

```bash
sudo bash root-toon.sh root
```

## Problemen?

Zie het uitgebreide bestand KALI_INSTRUCTIONS.md voor meer informatie en probleemoplossing.

## Let op

Deze scripts werken het beste op een fysieke Kali Linux machine, niet in een VM, omdat WiFi-hotspot functionaliteit niet altijd werkt in een VM.

## Na het rooten

Na het rooten kun je inloggen op je Toon met:
- Username: root
- Password: toon

```bash
ssh root@TOON_IP
``` 