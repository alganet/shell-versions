#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_build_dash ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/dash/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc automake autoconf dpkg-dev
	wget -O "${build_srcdir}.tar.gz" \
		"https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-$version.tar.gz"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	# TODO remove this dependency
	build_arch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"

	if test -f ./autogen.sh
	then 
		./autogen.sh
	else
		aclocal
		autoheader
		automake --add-missing
		autoconf
	fi

	./configure \
		--build="$build_arch" \
		--prefix="${SHVR_DIR_OUT}/dash_$version"

	make -j "$(nproc)"
	mkdir -p "${SHVR_DIR_OUT}/dash_${version}/bin"
	cp "src/dash" "${SHVR_DIR_OUT}/dash_$version/bin"
	
	"${SHVR_DIR_OUT}/dash_${version}/bin/dash" -c "echo dash version $version"
}
