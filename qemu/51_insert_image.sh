#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2017 ANSSI. All rights reserved.

# Insert the LV_IMAGE disk image as a Logical Volume with name LV_NAME and size
# LV_SIZE inside IMAGE which must be a CLIP OS prepared disk image.

# Safety settings: do not remove!
set -o errexit -o nounset -o pipefail

# TODO: Automatically compute ${LV_IMAGE_FILE} size

readonly IMAGE_FILE="${1:?IMAGE_FILE is needed}"
readonly VG_NAME="${2:?VG_NAME is needed}"
readonly LV_IMAGE_FILE="${3:?LV_IMAGE_FILE is needed}"
readonly LV_NAME="${4:?LV_NAME is needed}"

if [[ ! -f "${IMAGE_FILE}" ]]; then
    echo "${IMAGE_FILE} does not exist!"
    exit 1
fi
if [[ ! -f "${LV_IMAGE_FILE}" ]]; then
    echo "${LV_IMAGE_FILE} does not exist!"
    exit 1
fi

readonly IMAGE="$(basename ${IMAGE_FILE})"
readonly LV="$(basename ${LV_IMAGE_FILE})"

# We make use of libguestfs in the following commands to create the disk image
# where CLIP OS will be installed. This environment variable tells libguestfs
# to use directly QEMU-KVM without the need of the libvirt daemon.
export LIBGUESTFS_BACKEND=direct

echo "${IMAGE}: Adding ${LV} in ${LV_NAME}..."
guestfish --rw <<_EOF_
add-drive ${IMAGE_FILE} label:main
add-drive ${LV_IMAGE_FILE} label:lvimage readonly:true

run

copy-device-to-device /dev/disk/guestfs/lvimage /dev/${VG_NAME}/${LV_NAME}
_EOF_
echo "${IMAGE}: Adding ${LV} in ${LV_NAME}: OK"

# vim: set ts=4 sts=4 sw=4 et ft=sh:
