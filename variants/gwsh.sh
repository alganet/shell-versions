#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_gwsh ()
{
	cat <<-@
		gwsh_main
	@
}

shvr_build_gwsh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/gwsh/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc automake autoconf dpkg-dev
	wget -O "${build_srcdir}.tar.gz" \
		"https://api.github.com/repos/hvdijk/gwsh/tarball/${version}"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	# TODO remove this dependency
	build_arch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"

	./autogen.sh
	./configure \
		--build="$build_arch" \
		--prefix="${SHVR_DIR_OUT}/gwsh_$version"

	make -j "$(nproc)"
	mkdir -p "${SHVR_DIR_OUT}/gwsh_${version}/bin"
	cp "src/gwsh" "${SHVR_DIR_OUT}/gwsh_$version/bin"
	
	"${SHVR_DIR_OUT}/gwsh_${version}/bin/gwsh" -c "echo gwsh version $version"
}
