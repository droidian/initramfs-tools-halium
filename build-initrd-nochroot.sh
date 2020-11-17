#!/bin/bash
#
# build-initrd-nochroot - Builds an initramfs without using a chroot
# Copyright (C) 2020 Eugenio "g7" Paolantonio <me@medesimo.eu>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the <organization> nor the
#      names of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# This script is meant to be used on Debian-based distribution, and
# on the same target architecture.
# The goal is to obtain an initramfs in a debian packaging-friendly
# way.

set -e

info() {
	echo "I: $@"
}

warning() {
	echo "W: $@" >&2
}

error() {
	echo "E: $@" >&2
	exit 1
}

[ -n "${OUT}" ] || OUT="./out"

info "Starting initramfs build"

tmpdir="$(mktemp -d)"

cleanup() {
	rm -rf "${tmpdir}" || warning "Unable to clean-up temporary directory ${tmpdir}"
}
trap cleanup INT EXIT

# Copy initramfs-tools config directory
mkdir -p ${tmpdir}/etc/initramfs-tools
cp -R /etc/initramfs-tools/* ${tmpdir}/etc/initramfs-tools/

# Merge halium files
cp -av conf/halium ${tmpdir}/etc/initramfs-tools/conf.d
cp -av scripts/* ${tmpdir}/etc/initramfs-tools/scripts
cp -av hooks/* ${tmpdir}/etc/initramfs-tools/hooks

# Finally build
mkdir -p ${OUT}
exec /usr/sbin/mkinitramfs -d ${tmpdir}/etc/initramfs-tools -o ${OUT}/initrd.img-halium-generic -v
