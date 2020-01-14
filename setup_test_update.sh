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

main() {
    # Figure out current and next version
    local current_version="$(grep "version = " ../products/clipos/properties.toml | cut -f3 -d\ | sed 's|"||g')"
    local minor_version="${current_version##*.}"
    local next_version=$((minor_version+1))
    next_version="${current_version/%${minor_version}/${next_version}}"
    echo "[+] Preparing update from ${current_version} to ${next_version}..."

    # Setup update webroot for nginx running in ipsec-gw
    echo "[+] Setting up nginx webroot..."
    local webroot="synced_folders/ipsec-gw/update/"
    local dist="${webroot}/dist/${next_version}"
    mkdir -p "${webroot}/update/v1/clipos"
    mkdir -p "${dist}"
    echo "version = \"${next_version}\"" > "${webroot}/update/v1/clipos/version"

    # Copy clipos-core & clipos-efiboot
    echo "[+] Getting new clipos-core & clipos-efiboot..."
    local out="../out/clipos/${current_version}"
    cp "${out}/core/bundle/core.next.squashfs.verity.bundled" "${dist}/clipos-core"
    cp "${out}/efiboot/configure/linux.next.efi" "${dist}/clipos-efiboot"

    echo "[+] Signing clipos-core & clipos-efiboot..."
    local pubkey="../src/platform/updater/test/keys/pub"
    local privkey="../src/platform/updater/test/keys/priv"
    for f in "clipos-core" "clipos-efiboot"; do
        echo "" | rsign sign \
            "${dist}/${f}" \
            -p "${pubkey}" \
            -s "${privkey}" \
            -x "${dist}/${f}.sig" \
            -t "${next_version}"
    done

    echo "[+] Done"
}

main
