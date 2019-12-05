#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2017 ANSSI. All rights reserved.

# Insert an empty Logical Volume with name LV_NAME and size LV_SIZE inside
# IMAGE which must be a CLIP OS prepared disk image.

# Safety settings: do not remove!
set -o errexit -o nounset -o pipefail

readonly IMAGE_FILE="${1:?IMAGE_FILE is needed}"
readonly VG_NAME="${2:?VG_NAME is needed}"
readonly LV_NAME="${3:?LV_NAME is needed}"
readonly LV_SIZE="${4:?LV_SIZE is needed}"

if [[ ! -f "${IMAGE_FILE}" ]]; then
    echo "${IMAGE_FILE} does not exist!"
    exit 1
fi

readonly IMAGE="$(basename ${IMAGE_FILE})"

# We make use of libguestfs in the following commands to create the disk image
# where CLIP OS will be installed. This environment variable tells libguestfs
# to use directly QEMU-KVM without the need of the libvirt daemon.
export LIBGUESTFS_BACKEND=direct

echo "${IMAGE}: Adding empty ${LV_NAME}:${LV_SIZE}M..."
guestfish --rw <<_EOF_
add-drive ${IMAGE_FILE} label:main

run

lvcreate ${LV_NAME} ${VG_NAME} ${LV_SIZE}
_EOF_
echo "${IMAGE}: Adding empty ${LV_NAME}:${LV_SIZE}M: OK"

# vim: set ts=4 sts=4 sw=4 et ft=sh:
