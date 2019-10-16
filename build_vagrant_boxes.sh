#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2019 ANSSI. All rights reserved.

set -eu -o pipefail

main() {
    echo "[+] Building Vagrant boxes..."

    pushd boxes > /dev/null

    # Boxes to build:
    local -r boxes=(
        'ipsec-gw'
    )

    for box in "${boxes[@]}"; do
        echo "[+] Building '${box}' box..."

        # Clean up
        vagrant destroy "${box}" || true

        rm -rf '_tmp_package'
        vagrant up "${box}"

        # Until https://github.com/vagrant-libvirt/vagrant-libvirt/pull/1034 is
        # merged, we have to wait for the VM to shutdown before packaging it.
        vagrant ssh -c 'sudo poweroff' "${box}" || true
        sleep 5

        # Unfortunately we have to ask the user to manually give us access to
        # the image disk as libvirt will restore root as owner on shutdown.
        echo "[*] Please run 'sudo chmod a+r path/to/build_clipos-testbed_${box}.img'"
        echo ""
        read -p "[*] -->> Waiting for user confirmation (press enter here) <<-- "

        echo "[+] Packaging the '${box}' box..."
        vagrant package --output 'ipsec-gw.box' "${box}"

        echo "[+] Importing the '${box}' box..."
        vagrant box add --force \
            --name 'clipos-testbed/ipsec-gw' \
            'ipsec-gw.box'

        echo "[+] Cleaning up the '${box}' box..."
        rm 'ipsec-gw.box'
        vagrant destroy
    done

    popd > /dev/null

    echo "[+] Done"
}

main
