#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_posh ()
{
	cat <<-@
		posh_0.14.1
		posh_0.13.2
		posh_0.12.6
	@
}

shvr_build_posh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/posh/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc make autoconf automake
	wget -O "${build_srcdir}.tar.gz" \
		"https://salsa.debian.org/clint/posh/-/archive/debian/$version/posh-debian-$version.tar.gz"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	autoreconf -fi
	./configure \
		--prefix="${SHVR_DIR_OUT}/posh_$version"

	make -j "$(nproc)"
	mkdir -p "${SHVR_DIR_OUT}/posh_${version}/bin"
	cp "posh" "${SHVR_DIR_OUT}/posh_$version/bin"
	
	"${SHVR_DIR_OUT}/posh_${version}/bin/posh" -c "echo posh version $version"
}
