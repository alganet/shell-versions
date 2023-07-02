#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

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
