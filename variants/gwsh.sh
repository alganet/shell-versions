#!/usr/bin/env sh

# ISC License
#
# Copyright (c) 2023 Alexandre Gomes Gaigalas <alganet@gmail.com>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

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
