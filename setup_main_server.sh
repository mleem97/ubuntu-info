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

# Vorbereitung Ansible Server
sudo adduser ansible
sudo bash -c "echo 'ansible ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers"

# Vorbereitung Ansible Client
sudo apt install ansible ansible-lint sshpass -y
sudo adduser ansible

ANSIBLE_HOSTS="/etc/ansible/hosts"
echo "[ubuntuserver]
192.168.100.1 ansible_user=ansible ansible_ssh_pass=[PASSWORT] ansible_become_pass=[PASSWORT]" | sudo tee -a $ANSIBLE_HOSTS

# Ansible Playbooks erstellen
ANSIBLE_PLAYBOOK_DIR="$HOME/ansible-playbooks"
mkdir -p $ANSIBLE_PLAYBOOK_DIR

cat <<EOL > $ANSIBLE_PLAYBOOK_DIR/update_upgrade.yml
---
- hosts: ubuntuserver
  become: true
  gather_facts: yes
  tasks:
    - name: Warten, bis der APT-Lock freigegeben wird
      shell: while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 5; done;

    - name: Update APT-Paketliste
      apt:
        update_cache: yes
        force_apt_get: yes
        cache_valid_time: 3600

    - name: Perform a dist-upgrade.
      ansible.builtin.apt:
        upgrade: dist
        update_cache: yes

    - name: Check if a reboot is required.
      ansible.builtin.stat:
        path: /var/run/reboot-required
        get_checksum: no
      register: reboot_required_file

    - name: Reboot the server (if required).
      ansible.builtin.reboot:
      when: reboot_required_file.stat.exists and reboot_required_file is defined

    - name: Remove dependencies that are no longer required.
      ansible.builtin.apt:
        autoremove: yes

    - name: Lösche nicht mehr benötigte APT-Caches
      apt:
        autoclean: yes
EOL

cat <<EOL > $ANSIBLE_PLAYBOOK_DIR/file_copy.yml
---
- hosts: ubuntuserver
  become: true
  tasks:
    - name: Ordner anlegen
      file:
        path: /tmp/test
        state: directory
        owner: root
        group: root
        mode: '0755'
    
    - name: Datei kopieren
      copy:
        src: /home/andreas/samba/allesmeins
        dest: /tmp/test
        owner: root
        group: root
        mode: u=rwx,g=rx,o=rx
        backup: true  

    - name: Datei um Text erweitern
      blockinfile:
        path: /tmp/test/allesmeins
        block: |
          Dieser Text wurde von
          Ansible
          eingefügt
EOL

# Client Setup Funktion
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
