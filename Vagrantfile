# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2019 ANSSI. All rights reserved.

ENVNAME = "clipos-testbed"

Vagrant.configure("2") do |config|

  # Common settings for the libvirt provider
  config.vm.provider "libvirt" do |libvirt|
    # Do not use the directory name in which this Vagrantfile sits as prefix
    # to the libvirt domains:
    libvirt.default_prefix = "#{ENVNAME}"

    # Libvirt management network settings:
    libvirt.management_network_name = "#{ENVNAME}_management-network"
    libvirt.management_network_address = "172.27.254.0/24"
    libvirt.management_network_mode = "none"  # Do not NAT this bridge interface
  end

  # IPsec gateway based on Debian testing image
  config.vm.define "ipsec-gw" do |ipsecgw|
    ipsecgw.vm.box = "clipos-testbed/debian"

    # Main local network interface with internet access. CLIP OS workstations
    # and gateway will be connected to this network.
    ipsecgw.vm.network "private_network", libvirt__forward_mode: "nat",
      libvirt__network_name: "#{ENVNAME}_local-network",
      libvirt__dhcp_start: "172.27.1.11", libvirt__dhcp_stop: "172.27.1.99",
      ip: "172.27.1.10", libvirt__netmask: "255.255.255.0"

    # Provider-specific settings for this VM:
    ipsecgw.vm.provider "libvirt" do |libvirt|
      libvirt.cpus = 2
      libvirt.cputopology sockets: "1", cores: "1", threads: "2"
      libvirt.memory = 2048
      libvirt.graphics_type = "spice"
      libvirt.video_type = "qxl"
    end

    # Expose the "/vagrant" synced folder with 9p/virtio in mapped mode (rather
    # than the default NFS method):
    ipsecgw.vm.synced_folder "./synced_folders/ipsec-gw", "/vagrant",
      type: "9p", accessmode: "mapped", mount: true

    # Provisioning:
    ipsecgw.vm.provision "shell", path: "provisioning/ipsec-gw.sh"
  end

end

# vim: set ft=ruby ts=2 sts=2 sw=2 et ai tw=79:
