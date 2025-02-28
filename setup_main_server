#!/bin/bash

# Update und Upgrade des Systems
sudo apt update && sudo apt upgrade -y

# SSH einrichten und Firewall anpassen
sudo ufw enable
sudo ufw allow ssh
sudo ufw reload

# Firewall-Regeln für DHCP/DNS setzen
sudo ufw allow bootps comment 'Allow 67/UDP'
sudo ufw allow bootpc comment 'Allow 68/UDP'
sudo ufw allow 53/udp comment 'Allow DNS_53/UDP'
sudo ufw allow 53/tcp comment 'Allow DNS_53/TCP'
sudo ufw reload

# Feste IP-Adresse setzen
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
echo "network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s8:
      dhcp4: no
      addresses:
       - 192.168.100.1/24
      nameservers:
       addresses: [8.8.8.8, 9.9.9.9]" | sudo tee $NETPLAN_FILE

sudo chmod 600 $NETPLAN_FILE
sudo netplan apply

# Installation von dnsmasq und Konfiguration
sudo apt install dnsmasq -y

DNSMASQ_CONF="/etc/dnsmasq.conf"
echo "interface=enp0s8
bind-interfaces
dhcp-range=192.168.100.10,192.168.100.20,24h
except-interface=\"lo\"" | sudo tee $DNSMASQ_CONF

sudo systemctl restart dnsmasq.service

# Installation von nmap
sudo apt install nmap -y

# Installation und Konfiguration von Samba
sudo apt install samba -y
sudo mkdir -p /mnt/sambashare
sudo useradd -s /bin/false smbuser
sudo smbpasswd -a smbuser
sudo chown -R smbuser:smbuser /mnt/sambashare
sudo chmod -R 700 /mnt/sambashare

SMB_CONF="/etc/samba/smb.conf"
echo "[global]
   security = user
   map to guest = never

[SAMBA]
   valid users = smbuser
   path = /mnt/sambashare
   public = no
   writable = yes
   comment = Sambashare
   printable = no
   guest ok = no
   create mask = 0600
   directory mask = 0700" | sudo tee $SMB_CONF

sudo systemctl restart smbd.service

# Samba Firewall-Regeln setzen
sudo ufw allow samba
sudo ufw reload

# Installation und Konfiguration auf dem Client
CLIENT_SETUP() {
    echo "Konfiguration des Linux-Clients"
    sudo apt install cifs-utils -y
    mkdir -p $HOME/samba
    echo -e "username=smbuser\npassword=deinpasswort" | tee $HOME/.smbcredentials
    chmod 600 $HOME/.smbcredentials
    echo "//192.168.100.1/SAMBA $HOME/samba cifs credentials=$HOME/.smbcredentials,iocharset=utf8,x-systemd.requires=network-online.target,uid=1000,gid=1000,file_mode=0644,dir_mode=0755 0 0" | sudo tee -a /etc/fstab
    sudo mount -a
    echo "Samba-Client erfolgreich eingerichtet."
}

read -p "Soll der Client eingerichtet werden? (j/n): " SETUP_CLIENT
if [[ "$SETUP_CLIENT" == "j" ]]; then
    CLIENT_SETUP
fi

echo "Server-Einrichtung abgeschlossen!"
