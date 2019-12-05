#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2017 ANSSI. All rights reserved.

# Insert the content of TAR archive in the DM-Crypt/Integrity device in LV_NAME
# Logical Volume inside IMAGE which must be a CLIP OS prepared disk image.

# Safety settings: do not remove!
set -o errexit -o nounset -o pipefail

readonly IMAGE_FILE="${1:?IMAGE_FILE is needed}"
readonly VG_NAME="${2:?VG_NAME is needed}"
readonly KEY_FILE="${3:?KEY_FILE is needed}"
readonly TAR_FILE="${4:?TAR_FILE is needed}"
readonly LV_NAME="${5:?LV_NAME is needed}"

if [[ ! -f "${IMAGE_FILE}" ]]; then
    echo "${IMAGE_FILE} does not exist!"
    exit 1
fi
if [[ ! -f "${TAR_FILE}" ]]; then
    echo "${TAR_FILE} does not exist!"
    exit 1
fi

readonly IMAGE="$(basename ${IMAGE_FILE})"
readonly TAR="$(basename ${TAR_FILE})"

# We make use of libguestfs in the following commands to create the disk image
# where CLIP OS will be installed. This environment variable tells libguestfs
# to use directly QEMU-KVM without the need of the libvirt daemon.
export LIBGUESTFS_BACKEND=direct

luks_key="$(cat ${KEY_FILE})"

echo "${IMAGE}: Adding ${TAR} in ${LV_NAME}..."
guestfish --rw --keys-from-stdin <<_EOF_
add-drive ${IMAGE_FILE} label:main format:qcow2

run

luks-open /dev/${VG_NAME}/${LV_NAME} core_state
${luks_key}

mount /dev/mapper/core_state /
tar-in ${TAR_FILE} /
_EOF_
echo "${IMAGE}: Adding ${TAR} in ${LV_NAME}: OK"

# vim: set ts=4 sts=4 sw=4 et ft=sh:
