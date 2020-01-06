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
    pushd "${PROGPATH}" > /dev/null

    if [[ -z "$(vagrant box list 2>/dev/null | grep "clipos-testbed/ipsec-gw" | cut -f1 -d\ )" ]]; then
        echo "[+] Building Vagrant boxes..."
        ./build_vagrant_boxes.sh
    fi

    vagrant up

    popd > /dev/null
}

main
