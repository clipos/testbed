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
    if [[ -z "$(command -v cosmk)" ]]; then
        >&2 echo "[!] Could not find \"cosmk\". Aborting."
        exit 1
    fi

    local -r repo_root="$(cosmk repo-root-path)"
    local -r product="$(cosmk product-name)"
    local -r current_version="$(cosmk product-version)"

    # Figure out current and next minor version
    local minor_version="${current_version##*.}"
    local next_version=$((minor_version+1))
    next_version="${current_version/%${minor_version}/${next_version}}"
    echo "[+] Preparing update from ${current_version} to ${next_version}..."

    # Setup update webroot for nginx running in ipsec-gw
    echo "[+] Setting up nginx webroot..."
    local webroot="synced_folders/ipsec-gw/update/"
    local dist="${webroot}/dist/${next_version}"
    mkdir -p "${webroot}/update/v1/${product}"
    mkdir -p "${dist}"
    echo "version = \"${next_version}\"" > "${webroot}/update/v1/${product}/version"

    # Copy ${product}-core & ${product}-efiboot
    echo "[+] Getting new ${product}-core & ${product}-efiboot..."
    local out="../out/${product}/${current_version}"
    cp "${out}/core/bundle/core.next.squashfs.verity.bundled" "${dist}/${product}-core"
    cp "${out}/efiboot/configure/linux.next.efi" "${dist}/${product}-efiboot"

    echo "[+] Signing ${product}-core & ${product}-efiboot..."
    local pubkey="../src/platform/updater/test/keys/pub"
    local privkey="../src/platform/updater/test/keys/priv"
    for f in "${product}-core" "${product}-efiboot"; do
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
