#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2019 ANSSI. All rights reserved.

set -eu -o pipefail

echo " [*] Fix networkd configuration..."
for f in "50-vagrant-ens7.network" "99-dhcp.network"; do
    install -v -o 0 -g 0 -m 0644 "/vagrant/networkd/${f}" "/etc/systemd/network/${f}"
done

echo " [*] Restart systemd-networkd & systemd-resolved services..."
systemctl restart systemd-networkd systemd-resolved

echo " [*] Install the dummy IPsec PKI..."
install -v -o 0 -g 0 -m 0644 "/vagrant/pki/root-ca.cert.pem" "/etc/swanctl/x509ca/root-ca.cert.pem"
install -v -o 0 -g 0 -m 0644 "/vagrant/pki/server.cert.pem"  "/etc/swanctl/x509/server.cert.pem"
install -v -o 0 -g 0 -m 0600 "/vagrant/pki/server.key.pem"   "/etc/swanctl/private/server.key.pem"

echo " [*] Install the dummy IPsec PKI..."
install -v -o 0 -g 0 -m 0644 "/vagrant/office_net.conf"      "/etc/swanctl/conf.d/office_net.conf"

echo " [*] Restart strongswan-swanctl service..."
systemctl restart strongswan-swanctl.service

echo " [*] Setup hostname in /etc/hosts..."
echo "127.0.0.1 ipsec-gw" >> /etc/hosts

echo " [*] Setup nginx configuration for updates..."
ln -s /vagrant/https/update.clip-os.org.conf /etc/nginx/conf.d/update.clip-os.org.conf

echo " [*] Enable & start nginx..."
systemctl enable --now nginx

# vim: set ts=4 sts=4 sw=4 et ft=sh:
