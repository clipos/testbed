#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2019 ANSSI. All rights reserved.

ip netns exec ipsec0 nft flush ruleset
ip netns exec ipsec0 nft -f rules.nft
