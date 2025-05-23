#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_osh ()
{
	cat <<-@
		osh_0.24.0
		osh_0.23.0
	@
}

shvr_targets_osh ()
{
	cat <<-@
		osh_0.24.0
		osh_0.23.0
		osh_0.22.0
		osh_0.21.0
		osh_0.20.0
		osh_0.19.0
		osh_0.18.0
		osh_0.17.0
		osh_0.16.0
		osh_0.15.0
		osh_0.14.2
		osh_0.13.1
		osh_0.12.9
		osh_0.11.0
		osh_0.10.1
		osh_0.9.9
	@
}

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
