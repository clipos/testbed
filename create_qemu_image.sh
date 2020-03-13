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
readonly CORE_STATE_KEY="clipos"

main() {
    local runtime=""
    # Is libguestfs installed on the system and are we told to use it?
    if [[ ( -n "$(command -v guestfish)" ) && ( -n "${CLIPOS_USEHOST_TOOLS+x}" ) ]]; then
        runtime="host"
    # Is podman or docker available?
    elif [[ -n "$(command -v podman)" ]]; then
        runtime="podman"
    elif [[ -n "$(command -v docker)" ]]; then
        runtime="docker"
    else
        >&2 echo "[!] Could not find either \"podman\" or \"docker\". Aborting."
        >&2 echo "Set CLIPOS_USE_HOST_TOOLS="true" if you want to use guestfish from your system."
        exit 1
    fi

    # Are we running in a full CLIP OS project clone or standalone?
    if [[ -d "${PROGPATH}/../.repo" ]]; then
        if [[ -z "$(command -v cosmk)" ]]; then
            >&2 echo "[!] Could not find \"cosmk\". Aborting."
            exit 1
        fi

        local -r product="$(cosmk product-name)"
        local -r version="$(cosmk product-version)"
        local -r current="../out/${product}/${version}"

        local -r core="${current}/core/bundle/core.squashfs.verity.bundled"
        local -r efiboot="${current}/efiboot/bundle/efipartition.tar"
        local -r core_state="${current}/qemu/bundle/qemu-core-state.tar"

        local -r vg_name="mainvg"
        local -r core_lv_name="core_${version}"

        local -r output="../run/virtual_machines"
    else
        if [[ ${runtime} != "host" ]]; then
            >&2 echo "[!] Please install \"guestfish\" (libguestfs-tools). Aborting."
            exit 1
        fi
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

        local -r output="${PROGPATH}/run"
    fi

    echo "[*] Building QEMU image for ${product} ${version}"

    # Check for KVM availability and permission access
    local runtime_env=""
    if [[ ! -r "/dev/kvm" ]] || [[ ! -w "/dev/kvm" ]]; then
        # We could not find the KVM device or we do not have access to it
        # Force TCG backend to use QEMU without KVM support
        # See http://libguestfs.org/guestfs.3.html#backend-settings
        >&2 echo "[!] No support or access to KVM found. Running with TCG accel"
        export LIBGUESTFS_BACKEND_SETTINGS=force_tcg
        runtime_env="--env=LIBGUESTFS_BACKEND_SETTINGS"
    fi

    # Enable debug options for libguestfs
    # export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1

    # Make sure we operate from the root of the testbed repository
    cd "${PROGPATH}"

    local -r empty_disk_image="${output}/empty.qcow2"
    local -r core_state_keyfile="${output}/core_state.keyfile"
    mkdir -p "${output}"

    local prefix=""
    if [[ ${runtime} == "podman" || ${runtime} == "docker" ]]; then
        local user=""
        # Only try to run in non-privilege mode if using podman and /etc/sub{u,g}uid is configured
        if [[ ( -z "$(grep "$(id --user --name):" /etc/subuid)" ) || ( ${runtime} == "docker" ) ]]; then
            echo "[*] Running using privileged ${runtime} container"
            runtime="sudo ${runtime}"
            user="--user $(id --user):"
        else
            echo "[*] Running using unprivileged ${runtime} container"
            user="--user 0"
        fi
        # Image name including registry
        local -r image="$(cosmk ci-registry)"
        # Look for image
        ${runtime} inspect "${image}" &> /dev/null && rc=${?} || rc=${?}
        if [[ ${rc} -ne 0 ]]; then
            # Pull image from GitLab registry
            ${runtime} pull "${image}" && rc=${?} || rc=${?}
            if [[ ${rc} -ne '0' ]]; then
                >&2 echo "[!] Could not pull ${image} from GitLab registry. Aborting."
                exit 1
            fi
        fi
        local opts="--security-opt label=disable --rm -ti ${user} --volume ..:/mnt:rw --workdir /mnt/testbed ${runtime_env}"
        prefix="${runtime} run ${opts} ${image}"
    else
        echo "[*] Running using system installed guestfish"
    fi

    # Re-use cached empty disk image if available
    if [[ ! -f "${empty_disk_image}" ]] || [[ ! -f "${core_state_keyfile}" ]]; then
        echo "[*] Creating empty QEMU disk image"
        ${prefix} ./qemu/10_create_disk_image.sh "${empty_disk_image}" "${vg_name}" qcow2 20G

        # Sizes are in MB (See http://libguestfs.org/guestfish.1.html#lvcreate)
        ${prefix} ./qemu/20_insert_empty_lv.sh "${empty_disk_image}" "${vg_name}" "${core_lv_name}" 4096
        ${prefix} ./qemu/20_insert_empty_lv.sh "${empty_disk_image}" "${vg_name}" core_state 512
        ${prefix} ./qemu/20_insert_empty_lv.sh "${empty_disk_image}" "${vg_name}" core_swap 1024

        echo -n "${CORE_STATE_KEY}" > "${core_state_keyfile}"
        ${prefix} ./qemu/30_setup_dm_crypt_integrity.sh "${empty_disk_image}" "${vg_name}" \
            "${core_state_keyfile}" core_state
    else
        echo "[!] Re-using cached empty QEMU disk image!"
    fi

    local -r final_disk_image="${output}/main.qcow2"

    # Work on a copy of the cached empty disk image
    cp "${empty_disk_image}" "${final_disk_image}"

    ${prefix} ./qemu/50_insert_efiboot.sh "${final_disk_image}" "${efiboot}"

    ${prefix} ./qemu/51_insert_image.sh "${final_disk_image}" "${vg_name}" "${core}" "${core_lv_name}"

    # Install core_state initial content
    ${prefix} ./qemu/52_insert_fs_tar.sh "${final_disk_image}" "${vg_name}" \
        "${core_state_keyfile}" "${core_state}" core_state

    echo "[*] Done!"
}

main "${@}"

# vim: set ts=4 sts=4 sw=4 et ft=sh:
