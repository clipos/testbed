#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright © 2019 ANSSI. All rights reserved.

"""Start a CLIP OS virtual machine for testing in the testbed environment."""

import os

# Make sure that we are not running inside a virtual environment.
try:
    if os.environ["VIRTUAL_ENV"]:
        # Retrieve path to the virtualenv and all the items composing PATH:
        venv_path = os.environ["VIRTUAL_ENV"]
        path_items = os.environ["PATH"].split(":")
        new_path_items = path_items[:] # copy object to receive changes

        # Iterate on the PATH items and strip all items beginning by the
        # virtualenv path (using canonical paths):
        for path_component in path_items:
            if os.path.realpath(path_component).startswith(
                    os.path.realpath(venv_path)):
                new_path_items.remove(path_component)

        # Unset VIRTUAL_ENV and set new PATH (with virtualenv binaries path
        # stripped):
        del os.environ["VIRTUAL_ENV"]
        os.environ['PATH'] = ':'.join(new_path_items)
except KeyError:
    # if we land here, then either PATH or VIRTUAL_ENV is missing in the
    # environment, proceed silently (even if this is strange...)
    pass

import argparse
import libvirt
import shutil
import signal
import subprocess
import sys
from string import Template
from typing import Any, Dict, Iterator, List, Optional, Tuple

def main():
    if os.geteuid() == 0:
        print("Do not run as root!")
        sys.exit(1)

    parser = argparse.ArgumentParser(description='Run a CLIP OS VM in a libvirt based testbed.')
    parser.add_argument('product', metavar='name', help='Product name')
    parser.add_argument('version', metavar='version', help='Product version')

    args = parser.parse_args()
    product_name = args.product
    product_version = args.version

    libvirt_template = os.path.join(repo_root_path(), "testbed", "qemu", "clipos-qemu.xml")
    spawn_virtmanager = False
    ovmf_code = os.path.join(repo_root_path(), "out", product_name,
                             product_version, "efiboot", "bundle", "qemu-ovmf",
                             "OVMF_CODE.fd")
    ovmf_vars_template = os.path.join(repo_root_path(), "out", product_name,
                             product_version, "efiboot", "bundle", "qemu-ovmf",
                             "OVMF_VARS.fd")
    qcow2_image = os.path.join(repo_root_path(), "run", "virtual_machines", "main.qcow2")

    # Name used for libvirt domain. This name must not include any '+' sign as
    # when doing TPM emulation, libvirt passes the guest name to swtpm, which
    # then uses it as a CN, for which '+' signs have a special meaning.
    name = "{name}-testbed_{name}-qemu".format(name=product_name).replace('+', '--')

    # Look for qemu-system-x86_64
    emulator = "qemu-system-x86_64"
    emulator_binpath = shutil.which(emulator)
    if not emulator_binpath:
        print("[!] Could not find {!r} emulator!")
        sys.exit(1)

    # Get a connection handle to the system libvirt daemon:
    conn = libvirt.open('qemu:///system')
    if not conn:
        print("[!] Could not connect to the system libvirt daemon!")
        sys.exit(1)

    # Destroy existing domain with the same name
    for domain in conn.listAllDomains():
        if domain.name() == name:
            if domain.isActive():
                domain.destroy()
            domain.undefineFlags(
                libvirt.VIR_DOMAIN_UNDEFINE_MANAGED_SAVE |
                libvirt.VIR_DOMAIN_UNDEFINE_SNAPSHOTS_METADATA |
                libvirt.VIR_DOMAIN_UNDEFINE_NVRAM
            )

    # The runtime working directory: the location where the containers bundles
    # will be created and managed (to put it differently, this is our
    # /var/lib/docker...).
    working_dir = os.path.join(repo_root_path(), "run/virtual_machines", name)
    if os.path.exists(working_dir):
        # obliterate directory unconditionnally as we may already have
        # destroyed the associated libvirt domain
        shutil.rmtree(working_dir)
    os.makedirs(working_dir)

    workdir_ovmf_code = os.path.join(working_dir, "OVMF_code.fd")
    workdir_ovmf_vars_template = os.path.join(working_dir, "OVMF_vars_template.fd")
    workdir_ovmf_vars = os.path.join(working_dir, "OVMF_vars.fd")
    try:
        shutil.copy(ovmf_code, workdir_ovmf_code)
    except:
        print("[!] Could not copy '{}' to workdir!".format(ovmf_code))
        sys.exit(1)
    try:
        shutil.copy(ovmf_vars_template, workdir_ovmf_vars_template)
    except:
        print("[!] Could not copy '{}' to workdir!".format(ovmf_vars_template))
        sys.exit(1)

    workdir_qcow2_image = os.path.join(working_dir, "main.qcow2")
    try:
        shutil.copy(qcow2_image, workdir_qcow2_image)
        # TODO: Find out why the following command does not yield a valid image
        # subprocess.run(
        #     ["qemu-img", "create", "-f", "qcow2", "-b", qcow2_image, workdir_qcow2_image],
        #     check=True)
    except:
        print("[!] Could not create backing image for '{}' in workdir!".format(qcow2_image))
        sys.exit(1)

    # Do we have a TPM emulator installed? (i.e. is swtpm in $PATH?)
    is_swtpm_present = bool(shutil.which('swtpm'))
    tpm_support_xmlhunk = "<tpm model='tpm-tis'><backend type='emulator' version='2.0'></backend></tpm>"

    # We require libvirt >= 4.5.0 to get swtpm working, check the current
    # libvirt version:
    _int_libvirt_version = libvirt.getVersion()
    # According to libvirt docs, getVersion() returns the libvirt version
    # as an integer x where x = 1000000*major + 1000*minor + release.
    # Compare versions with a more Pythonic way (tuples):
    libvirt_version = (
        (_int_libvirt_version // 1000000),        # major
        ((_int_libvirt_version // 1000) % 1000),  # minor
        (_int_libvirt_version % 1000),            # release
    )
    libvirt_version_supports_swtpm = bool(libvirt_version >= (4, 5, 0))
    is_swtpm_usable = is_swtpm_present and libvirt_version_supports_swtpm

    if not is_swtpm_usable:
        if not is_swtpm_present:
            print(
                """[!] swtpm (libtpms-based TPM emulator) could not be found in
                PATH but is required by libvirt for the TPM emulation."""
            )
        if not libvirt_version_supports_swtpm:
            print(
                """[!] Your libvirt version is too old to support swtpm
                (libtpms-based TPM emulator): libvirt 4.5.0 at least is
                required but your libvirt version is currently
                {libvirt_version}."""
                .format(
                    libvirt_version=".".join([str(i) for i in libvirt_version]),
                )
            )
        print(
            """[!] TPM cannot be emulated: falling back to launch a libvirt
            virtual machine without any emulated TPM.""")

    # Generate domain XML
    with open(libvirt_template, 'r') as xmlfile:
        xmlcontents = xmlfile.read()
    xmltpl = Template(xmlcontents)
    xmldomain = xmltpl.substitute(
        domain_name=name,
        ovmf_firmware_code_filepath=workdir_ovmf_code,
        ovmf_firmware_vars_filepath=workdir_ovmf_vars,
        ovmf_firmware_vars_template_filepath=workdir_ovmf_vars_template,
        qemu_x86_64_binpath=emulator_binpath,
        qcow2_main_disk_image_filepath=workdir_qcow2_image,
        tpm_support=(tpm_support_xmlhunk if is_swtpm_usable else ""),
    )
    # Debug:
    # workdir_domain_xml = os.path.join(working_dir, "domain.xml")
    # with open(workdir_domain_xml, "w+") as xmlfile:
    #     xmlfile.write(xmldomain)

    libvirt_domain = conn.defineXML(xmldomain)
    if not libvirt_domain:
        print("[!] Could define libvirt domain!")
        sys.exit(1)
    # Start the domain
    libvirt_domain.create()
    print("")

    if spawn_virtmanager:
        print("[*] Spawning graphical virtual machine manager (\"virt-manager\")...")
        virt_manager_binpath = shutil.which("virt-manager")
        if not virt_manager_binpath:
            print("[!] Could not find virt-manager in PATH!")
            # virt-manager is expected to fork into background, i.e. the small
            # timeout
        subprocess.run(
            [virt_manager_binpath, "--connect", "qemu:///system", "--show-domain-console", name],
            timeout=2, check=True)
    else:
        print("[*] Retrieve the virtual machine IP address with:")
        print("$ virsh --connect qemu:///system domifaddr {name}".format(name=name))
        print("")
        print("[*] Connect locally via SSH with:")
        print("$ ssh -i cache/{product}/{version}/qemu/bundle/ssh_root \\"
              .format(product=product_name, version=product_version))
        print("      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \\")
        print("      root@<domain_ip>")

    print("")
    try:
        print("[*] Interrupt the virtual machine with Control+C (SIGINT).\n" +
              "[*] Note: this will kill the virtual machine.")
        signal.pause()
    except KeyboardInterrupt:
        print("[*] Stopping virtual machine")

    for domain in conn.listAllDomains():
        if domain.name() == name:
            if domain.isActive():
                domain.destroy()
            break


# Usage of a global variable (masked from imports due to the leading
# underscores) are to avoid uneeded recomputation by the function
# repo_root_path() each time it is being called:
__REPO_ROOT = None

def is_repo_root(path: str) -> bool:
    """Returns True if the given path contains a ".repo" directory."""
    return os.path.isdir(os.path.join(path, ".repo"))

def repo_root_path() -> str:
    """Guess the repo root directory path from the current working directory or
    (if the CWD does not seem to be a repo root) from the location of this
    file."""

    global __REPO_ROOT
    if __REPO_ROOT:
        return __REPO_ROOT

    path = os.path.normpath(os.getcwd())
    while os.path.split(path)[1]:
        if is_repo_root(path):
            break

        path = os.path.split(path)[0]
    else:
        # fallback to the location of this file if the CWD is not in the
        # repo root:
        path = os.path.normpath(os.path.dirname(__file__))
        while os.path.split(path)[1]:
            if is_repo_root(path):
                break

            path = os.path.split(path)[0]
        else:
            print("Could not find repo root!")
            sys.exit(1)

    __REPO_ROOT = path
    return __REPO_ROOT


if __name__ == "__main__":
    main()
