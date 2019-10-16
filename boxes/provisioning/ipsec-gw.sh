#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2019 ANSSI. All rights reserved.

# Provisioning script for the Debian IPsec gateway

set -eu -o pipefail

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

# Gets rid of "(Reading database ... 5%" output.
echo 'Dpkg::Use-Pty "0";' > /etc/apt/apt.conf.d/00usepty

sed -i 's|buster|testing|g' /etc/apt/sources.list

# Update both packages index and installed packages
apt-get -y -q update
apt-get -y -q dist-upgrade

# Install:
#   - strongSwan (with swanctl utilities and systemd interfacing)
#   - nftables (firewall)
#   - nginx (update server)
#   - supplementary handy tools for developer/tester convenience
apt-get -y -q install \
    charon-systemd \
    nftables \
    nginx \
    vim bash-completion tmux openssl tree htop

# Set appropriate hostname
echo "ipsec-gw" > /etc/hostname

# Installs the sshd-keygen oneshot service. This oneshot unit is required to
# re-generate the SSHD host keys that are automatically deleted when packing
# this VM as a box (`vagrant-libvirt` uses `virt-sysprep` which automatically
# deletes sshd host keys).
install -v -o 0 -g 0 -m 0644 \
    /vagrant/sshd-keygen.service \
    /etc/systemd/system/sshd-keygen.service
systemctl add-wants ssh.service sshd-keygen.service

sync

# vim: set ts=4 sts=4 sw=4 et ft=sh:
