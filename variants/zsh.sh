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

shvr_build_zsh ()
{
	version="$1"
	version_major="${version%%\.*}"

	if test "$version" = "$version_major"
	then return 1
	fi
	
	version_minor="${version#$version_major\.}"
	version_patch="${version_minor#*\.}"
	
	if test "$version_patch" = "$version_minor"
	then version_patch="0"
	else version_minor="${version_minor%\.*}"
	fi
	
	build_srcdir="${SHVR_DIR_SRC}/zsh/${version}"
	mkdir -p "${build_srcdir}"

	if 
		test "$version_major" -gt 4 -a "${version_minor}" -gt 0 ||
		test "$version_major" -gt 5
	then
		apt-get -y install \
			wget gcc make autoconf libtinfo-dev xz-utils
		wget -O "${build_srcdir}.tar.xz" \
			"https://downloads.sourceforge.net/project/zsh/zsh/$version/zsh-$version.tar.xz"
		tar --extract \
			--file="${build_srcdir}.tar.xz" \
			--strip-components=1 \
			--directory="${build_srcdir}"
	else
		apt-get -y install \
			wget gcc make autoconf libtinfo-dev
		wget -O "${build_srcdir}.tar.gz" \
			"https://downloads.sourceforge.net/project/zsh/zsh/$version/zsh-$version.tar.gz"
		tar --extract \
			--file="${build_srcdir}.tar.gz" \
			--strip-components=1 \
			--directory="${build_srcdir}"
	fi

	cd "${build_srcdir}"

	./Util/preconfig
	./configure \
		--prefix="${SHVR_DIR_OUT}/zsh_$version" \
		--disable-dynamic \
		--with-tcsetpgrp

	make -j "$(nproc)"

	mkdir -p "${SHVR_DIR_OUT}/zsh_${version}/bin"
	cp "Src/zsh" "${SHVR_DIR_OUT}/zsh_$version/bin"

	"${SHVR_DIR_OUT}/zsh_${version}/bin/zsh" --version
}
