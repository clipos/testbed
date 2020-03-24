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

Set up a CLIP OS virtualized testbed
------------------------------------

Set up the testbed with:

```
$ ./setup_testbed.sh
```

Running `cosmk test run` in the CLIP OS development tree will now spawn a CLIP
OS QEMU VM in this environment.
