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

# Default LUKS passphrase for the Core State partition.
# WARNING: This is suitable only to create test QEMU virtual machine images and
# MUST NOT BE USED to install production systems.
readonly CORE_STATE_KEY="core_state_key"

main() {
    # Are we running in a full CLIP OS project clone or standalone?
    if [[ -d "${PROGPATH}/../.repo" ]]; then
        if [[ -z "$(command -v cosmk)" ]]; then
            >&2 echo "[!] Could not find \"cosmk\". Aborting."
            exit 1
        fi
        # TODO: Read this from repo root config.toml (not yet implemented)
        local -r product="clipos"

        local -r repo_root="$(cosmk repo-root-path)"
        local -r version="$(cosmk product-version ${product})"
        local -r current="${repo_root}/out/${product}/${version}"

        local -r core="${current}/core/bundle/core.squashfs.verity.bundled"
        local -r efiboot="${current}/efiboot/bundle/efipartition.tar"
        local -r core_state="${current}/qemu/bundle/qemu-core-state.tar"

        local -r vg_name="mainvg"
        local -r core_lv_name="core_${version}"

        local -r out="${repo_root}/out/${product}/${version}/qemu/bundle"
        local -r cache="${repo_root}/cache/${product}/${version}/qemu/bundle"
    else
        if [[ "${#}" -ne 5 ]]; then
            >&2 echo "[!] Invalid number of arguments!"
            >&2 echo "Usage: ${0} <product> <version> <core> <efiboot> <state>"
            exit 1
        fi
        local -r product="${1}"
        local -r version="${2}"

        local -r core="$(realpath --relative-to=${PROGPATH} ${3})"
        local -r efiboot="$(realpath --relative-to=${PROGPATH} ${4})"
        local -r core_state="$(realpath --relative-to=${PROGPATH} ${5})"

        local -r vg_name="mainvg"
        local -r core_lv_prefix="core_${version}"

        local -r out="${PROGPATH}/run"
        local -r cache="${PROGPATH}/run"
    fi

    # Check for KVM availability and permission access
    if [[ ! -r "/dev/kvm" ]] || [[ ! -w "/dev/kvm" ]]; then
        # We could not find the KVM device or we do not have access to it
        # Force TCG backend to use QEMU without KVM support
        # See http://libguestfs.org/guestfs.3.html#backend-settings
        >&2 echo "[!] No support or access to KVM found. Running with TCG accel"
        export LIBGUESTFS_BACKEND_SETTINGS=force_tcg
    fi

    # Enable debug options for libguestfs
    # export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1

    # Make sure we operate from the root of the testbed repository
    cd "${PROGPATH}"

    local -r empty_disk_image="${cache}/empty.qcow2"
    local -r core_state_keyfile="${cache}/core_state.keyfile"

    # Re-use cached empty disk image if available
    if [[ ! -f "${empty_disk_image}" ]] || [[ ! -f "${core_state_keyfile}" ]]; then
        echo "[*] Creating empty QEMU disk image"
        ./qemu/10_create_disk_image.sh "${empty_disk_image}" "${vg_name}" qcow2 20G

        # Sizes are in MB (See http://libguestfs.org/guestfish.1.html#lvcreate)
        ./qemu/20_insert_empty_lv.sh "${empty_disk_image}" "${vg_name}" "${core_lv_name}" 4096
        ./qemu/20_insert_empty_lv.sh "${empty_disk_image}" "${vg_name}" core_state 512
        ./qemu/20_insert_empty_lv.sh "${empty_disk_image}" "${vg_name}" core_swap 1024

        echo -n "${CORE_STATE_KEY}" > "${core_state_keyfile}"
        ./qemu/30_setup_dm_crypt_integrity.sh "${empty_disk_image}" "${vg_name}" \
            "${core_state_keyfile}" core_state
    else
        echo "[!] Re-using cached empty QEMU disk image!"
    fi

    local -r final_disk_image="${out}/main.qcow2"

    # Work on a copy of the cached empty disk image
    cp "${empty_disk_image}" "${final_disk_image}"

    ./qemu/50_insert_efiboot.sh "${final_disk_image}" "${efiboot}"

    ./qemu/51_insert_image.sh "${final_disk_image}" "${vg_name}" "${core}" "${core_lv_name}"

    # Install core_state initial content
    ./qemu/52_insert_fs_tar.sh "${final_disk_image}" "${vg_name}" \
        "${core_state_keyfile}" "${core_state}" core_state
}

main "${@}"

# vim: set ts=4 sts=4 sw=4 et ft=sh:
