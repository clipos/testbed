#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2019 ANSSI. All rights reserved.

set -eu -o pipefail

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

# Set appropriate hostname
echo " [*] Setup hostname to: '${HOSTNAME}'..."
HOSTNAME="ipsec-gw"
hostnamectl set-hostname "${HOSTNAME}"
echo "${HOSTNAME}" > /etc/hostname
echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts

echo " [*] Fix networkd configuration..."
for f in "50-vagrant-ens7.network" "99-dhcp.network"; do
    install -v -o 0 -g 0 -m 0644 "/vagrant/networkd/${f}" "/etc/systemd/network/${f}"
done

echo " [*] Restart systemd-networkd & systemd-resolved services..."
systemctl restart systemd-networkd systemd-resolved

# Update both packages index and installed packages
apt-get -y -q update
apt-get -y -q dist-upgrade

# Install:
#   - strongSwan (with swanctl utilities and systemd interfacing)
#   - nftables (firewall)
#   - nginx (update server)
#   - chrony (NTP client)
#   - rsyslog & rsyslog-relp (log forwarding with RELP support)
apt-get -y -q install \
    charon-systemd \
    nftables \
    nginx \
    chrony \
    rsyslog rsyslog-relp

echo " [*] Install the dummy IPsec PKI..."
install -v -o 0 -g 0 -m 0644 "/vagrant/pki/root-ca.cert.pem" "/etc/swanctl/x509ca/root-ca.cert.pem"
install -v -o 0 -g 0 -m 0644 "/vagrant/pki/server.cert.pem"  "/etc/swanctl/x509/server.cert.pem"
install -v -o 0 -g 0 -m 0600 "/vagrant/pki/server.key.pem"   "/etc/swanctl/private/server.key.pem"

echo " [*] Install the dummy IPsec PKI..."
install -v -o 0 -g 0 -m 0644 "/vagrant/strongswan/office_net.conf" "/etc/swanctl/conf.d/office_net.conf"

echo " [*] Create strongSwan user..."
install -v -o 0 -g 0 -m 755 -d "/etc/sysusers.d"
install -v -o 0 -g 0 -m 644 "/vagrant/strongswan/sysusers.conf" "/etc/sysusers.d/strongswan.conf"
systemd-sysusers strongswan.conf

echo " [*] Install strongSwan unit drop-in..."
install -v -o 0 -g 0 -m 755 -d "/etc/systemd/system/strongswan.service.d"
install -v -o 0 -g 0 -m 644 "/vagrant/strongswan/security.conf" \
    "/etc/systemd/system/strongswan.service.d/security.conf"

echo " [*] Update strongSwan configuration..."
sed -i \
    's|# socket = unix://${piddir}/|socket = unix:///run/ipsec/|g' \
    "/etc/strongswan.d/swanctl.conf" \
    "/etc/strongswan.d/charon/vici.conf"
chown -R root:ipsec \
    "/etc/strongswan.conf" \
    "/etc/strongswan.d" \
    "/etc/swanctl"
chmod -R ug+rX \
    "/etc/strongswan.conf" \
    "/etc/strongswan.d" \
    "/etc/swanctl"
plugins=(
    "aesni.conf" "agent.conf" "bypass-lan.conf" "connmark.conf" "counters.conf"
    "dnskey.conf" "eap-mschapv2.conf" "fips-prf.conf" "gcm.conf" "gmp.conf"
    "md5.conf" "mgf1.conf" "pgp.conf" "rc2.conf" "sha1.conf" "sshkey.conf"
    "xauth-generic.conf" "xcbc.conf"
)
for p in "${plugins[@]}"; do
    sed -i 's/load = yes/# load = yes/g' "/etc/strongswan.d/charon/${p}"
done

echo " [*] Install nftables rules..."
install -v -o 0 -g 0 -m 0600 "/vagrant/nft/apply.nft" "/etc/nftables.conf"
install -v -o 0 -g 0 -m 0600 "/vagrant/nft.ipsec0/rules.nft" "/etc/nftables.ipsec0.conf"

echo " [*] Enable nftables..."
systemctl enable --now nftables.service

echo " [*] Install Network namespace & XFRM interface unit..."
install -v -o 0 -g 0 -m 644 "/vagrant/strongswan/netns@.service" "/etc/systemd/system/netns@.service"
systemctl daemon-reload
systemctl enable --now netns@ipsec0.service

echo " [*] Restart strongSwan service..."
systemctl daemon-reload
systemctl restart strongswan.service

echo " [*] Create chrony-ipsec user..."
install -v -o 0 -g 0 -m 644 "/vagrant/chronyd/sysusers.conf" "/etc/sysusers.d/chrony.conf"
systemd-sysusers chrony.conf

install -v -o 0 -g 0 -m 0644 "/vagrant/chronyd/chrony.conf" "/etc/chrony/chrony.conf"
install -v -o 0 -g 0 -m 0644 "/vagrant/chronyd/chrony-ipsec.keys" "/etc/chrony/chrony-ipsec.keys"
install -v -o 0 -g 0 -m 0644 "/vagrant/chronyd/chrony-ipsec.conf" "/etc/chrony/chrony-ipsec.conf"
install -v -o 0 -g 0 -m 0644 "/vagrant/chronyd/chrony-ipsec.service" "/etc/systemd/system/chrony-ipsec.service"
install -v -o 0 -g 0 -m 0644 "/vagrant/chronyd/chrony.service" "/etc/systemd/system/chrony.service"
install -v -o 0 -g 0 -m 0644 "/vagrant/chronyd/tmpfiles.conf" "/etc/tmpfiles.d/chrony.conf"
install -v -o 0 -g 0 -m 0644 "/vagrant/chronyd/usr.sbin.chronyd" "/etc/apparmor.d/local/usr.sbin.chronyd"
systemd-tmpfiles --create chrony.conf

echo " [*] Install chrony unit drop-in..."
install -v -o 0 -g 0 -m 755 -d "/etc/systemd/system/chronyd-ipsec.service.d"
install -v -o 0 -g 0 -m 644 "/vagrant/ipsec0.conf" \
    "/etc/systemd/system/chronyd-ipsec.service.d/ipsec0.conf"

echo " [*] Restart apparmor to apply new chrony rules"
systemctl restart apparmor
echo " [*] Enable chronyd-ipsec..."
systemctl daemon-reload
systemctl enable --now chrony-ipsec.service
systemctl restart chrony.service
systemctl restart chrony-ipsec.service

echo " [*] Create rsyslog user..."
install -v -o 0 -g 0 -m 644 "/vagrant/rsyslog/sysusers.conf" "/etc/sysusers.d/rsyslog.conf"
systemd-sysusers rsyslog.conf

echo " [*] Install rsyslog configuration..."
install -v -o 0 -g 0 -m 0644 "/vagrant/rsyslog/rsyslog.conf" "/etc/rsyslog.conf"

echo " [*] Install rsyslog unit drop-in..."
install -v -o 0 -g 0 -m 755 -d "/etc/systemd/system/rsyslog.service.d"
install -v -o 0 -g 0 -m 644 "/vagrant/ipsec0.conf" \
    "/etc/systemd/system/rsyslog.service.d/ipsec0.conf"

echo " [*] Enable rsyslog..."
systemctl daemon-reload
systemctl enable --now rsyslog.service
systemctl restart rsyslog.service

echo " [*] Install nginx configuration for updates..."
for f in "update.clip-os.org.conf" "update.clip-os.org-key.pem" "update.clip-os.org.pem"; do
    install -v -o 0 -g 0 -m 0644 "/vagrant/nginx/${f}" "/etc/nginx/conf.d/${f}"
done

echo " [*] Install nginx unit drop-in..."
install -v -o 0 -g 0 -m 755 -d "/etc/systemd/system/nginx.service.d"
install -v -o 0 -g 0 -m 644 "/vagrant/ipsec0.conf" \
    "/etc/systemd/system/nginx.service.d/ipsec0.conf"

echo " [*] Restart nginx service..."
systemctl daemon-reload
systemctl restart nginx.service

echo " [*] Done"

# vim: set ts=4 sts=4 sw=4 et ft=sh:
