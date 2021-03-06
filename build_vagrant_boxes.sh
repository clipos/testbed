#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2019 ANSSI. All rights reserved.

# Safety settings: do not remove!
set -o errexit -o nounset -o pipefail

# Do not run as root
if [[ "${EUID}" == 0 ]]; then
    >&2 echo "[*] Do not run as root!"
    exit 1
fi

# Get the basename of this program and the directory path to itself:
readonly PROGNAME="${BASH_SOURCE[0]##*/}"
readonly PROGPATH="$(realpath "${BASH_SOURCE[0]%/*}")"

main() {
    echo "[+] Building Vagrant boxes..."

    pushd "${PROGPATH}/boxes" > /dev/null

    # Boxes to build:
    local -r boxes=(
        'debian'
    )

    for box in "${boxes[@]}"; do
        echo "[+] Building '${box}' box..."

        # Clean up
        vagrant destroy --force "${box}" || true

        rm -rf '_tmp_package'
        vagrant up "${box}"
        sleep 5

        # Until https://github.com/vagrant-libvirt/vagrant-libvirt/pull/1034 is
        # merged, we have to wait for the VM to shutdown before packaging it.
        vagrant ssh -c 'sudo poweroff' "${box}" || true
        sleep 5

        # Unfortunately we have to manually give us access to the image disk as
        # libvirt will restore root as owner on shutdown.
        local boxname="build_clipos-testbed_${box}"
        local cmd="virsh --connect qemu:///system domblklist ${boxname}"
        local image="$(${cmd} | grep "vda" | awk '{print $2}')"

        if [ -z "$image" ]; then
            echo "[!] Warning: No image for the '${boxname}' domain was found."
            vagrant destroy --force "${box}" || true
        else
            echo "[!] Warning: Giving everyone read access to '${image}'"
            sudo chmod a+r "${image}"

            echo "[+] Packaging the '${box}' box..."
            vagrant package --output "${box}.box" "${box}"

            echo "[+] Importing the '${box}' box..."
            vagrant box add --force --name "clipos-testbed/${box}" "${box}.box"

            echo "[+] Cleaning up the '${box}' box..."
            rm "${box}.box"
            vagrant destroy --force "${box}" || true
        fi
    done

    popd > /dev/null

    echo "[+] Done"
}

main

# vim: set ts=4 sts=4 sw=4 et ft=sh:
