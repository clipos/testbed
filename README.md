Resources to build and provision the CLIP OS virtualized testbed
================================================================

Overview
--------

This repository contains all the material to create and use a CLIP OS
virtualized testbed with Vagrant using libvirt through QEMU/KVM.

Requirements
------------

- [Vagrant](https://www.vagrantup.com/) with
  [`vagrant-libvirt`](https://github.com/vagrant-libvirt/vagrant-libvirt)
- [libguestfs](http://libguestfs.org/) for
  [`virt-sysprep`](http://libguestfs.org/virt-sysprep.1.html) which is required
  by `vagrant-libvirt` to produce a Vagrant box out of an exisiting VM thanks
  to the command `vagrant package`

Build the Vagrant boxes
-----------------------

Build and import the box for the IPsec gateway:

```
$ ./build_vagrant_boxes.sh
```

Spin up a CLIP OS virtualized testbed with Vagrant and libvirt
--------------------------------------------------------------

Setup the testbed with:

```
$ vagrant up
```

Running `cosmk spawn` or `sujust run` in the CLIP OS development tree will now
spawn a CLIP OS QEMU VM in this environment.
