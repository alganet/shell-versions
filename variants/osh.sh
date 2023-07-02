#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_build_osh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/osh/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc make
	wget -O "${build_srcdir}.tar.gz" \
		"https://www.oilshell.org/download/oil-${version}.tar.gz"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	./configure \
		--without-readline \
		--prefix="${SHVR_DIR_OUT}/osh_$version"

	make -j "$(nproc)"
	mkdir -p "${SHVR_DIR_OUT}/osh_${version}/bin"
	cp "_bin/oil.ovm" "${SHVR_DIR_OUT}/osh_$version/bin/osh"
	
	"${SHVR_DIR_OUT}/osh_${version}/bin/osh" -c "echo osh version $version"
}
