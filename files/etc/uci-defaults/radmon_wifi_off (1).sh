#!/bin/sh
# Radius Monitor V2 Auto Installer
# Author: Maizil <https://github.com/maizil41>

RED="\e[1;91m"
PURPLE="\e[1;95m"
CYAN="\e[1;96m"
YELLOW="\e[1;93m"
BLUE="\e[1;94m"
GREEN="\e[1;92m"
ORANGE="\e[1;91m"
PINK="\e[1;95m"
LIGHT_BLUE="\e[1;94m"
LIGHT_CYAN="\e[1;96m"
LIGHT_GREEN="\e[1;92m"
LIGHT_YELLOW="\e[1;93m"
GRAY="\e[0;37m"
LIGHT_GRAY="\e[0;37m"
BROWN="\e[0;33m"
RESET="\e[0m"



msg "Step 2: seting myqsl"
sed -i "s/option enabled '0'/option enabled '1'/g" /etc/config/mysqld && /etc/init.d/mysqld start
if ! /etc/init.d/mysqld status >/dev/null 2>&1; then
    echo -e "${RED}Gagal memulai Mariadb. Keluar...${RESET}"
    exit 1
fi
[ -e /tmp/sexpect.sock ] && rm -f /tmp/sexpect.sock
sexpect -s /tmp/sexpect.sock spawn mysql_secure_installation -u root
sleep 1
sexpect -s /tmp/sexpect.sock expect -re "Enter current password for root \(enter for none\):"
sexpect -s /tmp/sexpect.sock send -enter
sleep 1
sexpect -s /tmp/sexpect.sock expect -re "Switch to unix_socket authentication \[Y/n\]"
sexpect -s /tmp/sexpect.sock send "n" -enter
sleep 1
sexpect -s /tmp/sexpect.sock expect -re "Change the root password\? \[Y/n\]"
sexpect -s /tmp/sexpect.sock send "y" -enter
sleep 1
sexpect -s /tmp/sexpect.sock expect -re "New password:"
sexpect -s /tmp/sexpect.sock send "radmon" -enter
sleep 1
sexpect -s /tmp/sexpect.sock expect -re "Re-enter new password:"
sexpect -s /tmp/sexpect.sock send "radmon" -enter
sleep 1
sexpect -s /tmp/sexpect.sock expect -re "Remove anonymous users\? \[Y/n\]"
sexpect -s /tmp/sexpect.sock send "y" -enter
sleep 1
sexpect -s /tmp/sexpect.sock expect -re "Disallow root login remotely\? \[Y/n\]"
sexpect -s /tmp/sexpect.sock send "n" -enter
sleep 1
sexpect -s /tmp/sexpect.sock expect -re "Remove test database and access to it\? \[Y/n\]"
sexpect -s /tmp/sexpect.sock send "y" -enter
sleep 1
sexpect -s /tmp/sexpect.sock expect -re "Reload privilege tables now\? \[Y/n\]"
sexpect -s /tmp/sexpect.sock send "y" -enter
sleep 1
sexpect -s /tmp/sexpect.sock close
ps | grep sexpect | grep -v grep | awk '{print $1}' | xargs -r kill -9


sleep 1

msg "Step 2: buat database"

if mysql -u root -pradmon -e "USE radmon" >/dev/null 2>&1; then
    echo -e "${YELLOW}Menghapus database radmon yang sudah ada...${RESET}"
    if ! mysql -u root -pradmon -e "DROP DATABASE radmon"; then
        echo -e "${RED}Gagal menghapus database radmon. Keluar...${RESET}"
        exit 1
    fi
fi

if ! mysql -u root -pradmon -e "CREATE DATABASE radmon CHARACTER SET utf8"; then
    echo -e "${RED}Gagal membuat database. Keluar...${RESET}"
    exit 1
fi

if ! mysql -u root -pradmon -e "GRANT ALL ON radmon.* TO 'radmon'@'localhost' IDENTIFIED BY 'radmon' WITH GRANT OPTION"; then
    echo -e "${RED}Gagal memberikan hak akses ke database. Keluar...${RESET}"
    exit 1
fi

sleep 1
msg "Step 2: hpus berkas lama"
rm -f /etc/chilli/up.sh >/dev/null 2>&1
rm -rf /etc/freeradius3 >/dev/null 2>&1
rm -rf /etc/config/chilli >/dev/null 2>&1
rm -rf /etc/init.d/chilli >/dev/null 2>&1
rm -rf /usr/share/freeradius3 >/dev/null 2>&1

# Step 1: Add link Hotspotlogin And radmonMonitor
msg "Step 2: unzip bahan"
mv /www/T.zip /.

msg "Step 2: extra file"
cd /.
if ! unzip -o T.zip >/dev/null 2>&1; then
    echo -e "${RED}Gagal mengekstrak file. Keluar...${RESET}"
    exit 1
fi
rm -rf T.zip >/dev/null 2>&1

sleep 1 

msg "Step 2: perizinan"
chmod +x /etc/init.d/chilli >/dev/null 2>&1
chmod +x /usr/bin/radmon-* >/dev/null 2>&1
chmod 644 -R /etc/freeradius3 >/dev/null 2>&1


sleep 1 

msg "Step 2: Configure Freeradius"
ln -sf /usr/share/RadMonv2 /www/RadMonv2
ln -sf /usr/share/hotspotlogin /www/hotspotlogin
ln -sf /usr/share/adminer /www/adminer


sleep 1 

msg "Step 2: Configure Freeradius"
cd /etc/freeradius3/mods-enabled || { echo -e "${RED}Gagal masuk ke direktori mods-enabled. Keluar...${RESET}"; exit 1; }
ln -sf ../mods-available/always
ln -sf ../mods-available/attr_filter
ln -sf ../mods-available/chap
ln -sf ../mods-available/detail
ln -sf ../mods-available/digest
ln -sf ../mods-available/eap
ln -sf ../mods-available/exec
ln -sf ../mods-available/expiration
ln -sf ../mods-available/expr
ln -sf ../mods-available/files
ln -sf ../mods-available/logintime
ln -sf ../mods-available/mschap
ln -sf ../mods-available/pap
ln -sf ../mods-available/preprocess
ln -sf ../mods-available/radutmp
ln -sf ../mods-available/realm
ln -sf ../mods-available/sql
ln -sf ../mods-available/sradutmp
ln -sf ../mods-available/unix
cd || { echo -e "${RED}Gagal kembali ke direktori home. Keluar...${RESET}"; exit 1; }


sleep 1 

msg "Step 2: Configure Freeradius"
cd /etc/freeradius3/sites-enabled || { echo -e "${RED}Gagal masuk ke direktori sites-enabled. Keluar...${RESET}"; exit 1; }
ln -sf ../sites-available/default
ln -sf ../sites-available/inner-tunnel
cd || { echo -e "${RED}Gagal kembali ke direktori home. Keluar...${RESET}"; exit 1; }


sleep 1

msg "Step 2: Co"
ln -sf /usr/bin/php-cli /usr/bin/php

sleep 1 


msg "Step 2: buat sql"
cd /www/RadMonv2 || { echo -e "${RED}Gagal masuk ke direktori RadMonv2. Keluar...${RESET}"; exit 1; }
if ! mysql -u root -pradmon radmon < radmonv2.sql; then
    echo -e "${RED}Gagal menginstall database RadMon. Keluar...${RESET}"
    exit 1
fi


sleep 1

msg "Step 2: buat crontab"
(crontab -l; echo "* * * * * /usr/bin/radmon-kuota >/dev/null 2>&1") | crontab -
(crontab -l; echo "0 0 * * * rm -f /www/RadMonv2/voucher/tmp/*.png >/dev/null 2>&1") | crontab -


sleep 1

msg "Step 2: Configure network"
uci set network.@device[0].ports='eth0.1'

uci set network.radius=device
uci set network.radius.name='br-radius'
uci set network.radius.type='bridge'
uci set network.radius.ipv6='0'
uci add_list network.radius.ports='eth0'

uci set network.hotspot=interface
uci set network.hotspot.proto='static'
uci set network.hotspot.device='br-radius'
uci set network.hotspot.ipaddr='10.10.30.1'
uci set network.hotspot.netmask='255.255.255.0'

uci set network.chilli=interface
uci set network.chilli.proto='none'
uci set network.chilli.device='tun0'

uci commit network



sleep 1

msg "Step 2: set firewall"
uci set firewall.coova_chilli=zone
uci set firewall.coova_chilli.name='coova_chilli'
uci set firewall.coova_chilli.input='ACCEPT'
uci set firewall.coova_chilli.output='ACCEPT'
uci set firewall.coova_chilli.forward='REJECT'
uci add_list firewall.coova_chilli.network='chilli'

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='coova_chilli'
uci set firewall.@forwarding[-1].dest='wan'

uci add_list firewall.@zone[0].network='hotspot'

uci commit firewall

sleep 1
# Step 5: Configure MySQL / Maridb
msg "Step 1: Configure MySQL / Maridb"
bash /etc/init.d/radiusd restart
bash /etc/init.d/radiusd reload
bash /etc/init.d/chilli restart
bash /etc/init.d/chilli reload


# Log success
msg "Radmon Setup settings successfully applied..."

# Remove this script after successful execution
rm -f /etc/uci-defaults/$(basename $0)

