Resources to build and provision the CLIP OS virtualized testbed
================================================================

Overview
--------

This repository contains all the material to create and use a CLIP OS
virtualized testbed with Vagrant using libvirt through QEMU/KVM.

Packer is used in order to build up Vagrant boxes (i.e. base virtual machines
images for Vagrant).

Requirements
------------

- [Vagrant](https://www.vagrantup.com/) with
  [`vagrant-libvirt`](https://github.com/vagrant-libvirt/vagrant-libvirt)
- [Packer](https://www.packer.io/)
- [libguestfs](http://libguestfs.org/) for
  [`virt-sysprep`](http://libguestfs.org/virt-sysprep.1.html) which is required
  by `vagrant-libvirt` to produce a Vagrant box out of an exisiting VM thanks
  to the command `vagrant package`

Initial setup
-------------

Depending on your `libvirt` setup, you may need to give your current user
access to the `libvirt` storage directory for QEMU images using ACLs:

```
$ sudo setfacl -dm u:<username>:rw /var/lib/libvirt/images
```

Build the Vagrant boxes
-----------------------

Build and import the box for the IPsec gateway:

```
$ cd boxes/ipsec-gw
$ ./yaml2json template.yml | packer build -force -
$ vagrant box add --force --name "clipos-testbed/ipsec-gw" output/package.box
```

Spin up a CLIP OS virtualized testbed with Vagrant and libvirt
--------------------------------------------------------------

Setup the testbed with:

```
$ vagrant up
```

Running `cosmk spawn` or `sujust run` in the CLIP OS development tree will now
spawn a CLIP OS QEMU VM in this environment.
