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

shvr_build_bash ()
{
	version="$1"
	version_major="${version%%\.*}"
	
	if test "$version" = "$version_major"
	then return 1
	fi
	
	version_minor="${version#$version_major\.}"
	version_patch="${version_minor#*\.}"
	
	if test "$version_patch" = "$version_minor"
	then return 1
	else version_minor="${version_minor%\.*}"
	fi
	
	version_baseline="${version_major}.${version_minor}"
	build_srcdir="${SHVR_DIR_SRC}/bash/${version_baseline}"
	mkdir -p "${build_srcdir}"

	if test "$version_baseline" = "4.0"
	then apt-get -y install \
			wget patch gcc bison make autoconf
	elif test "$version_baseline" = "3.0"
	then apt-get -y install \
			wget patch gcc bison make ncurses-dev
	else apt-get -y install \
			wget patch gcc bison make
	fi
	
	wget -O "${build_srcdir}.tar.gz" \
		"https://ftp.gnu.org/gnu/bash/bash-${version_baseline}.tar.gz"
	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	mkdir -p "${build_srcdir}-patches"
	patch_i=0
	while test $patch_i -lt $version_patch
	do
		patch_i=$((patch_i + 1))
		patch_n="$(printf '%03d' "$patch_i")"
		url="https://ftp.gnu.org/gnu/bash/bash-${version_baseline}-patches/bash${version_major}${version_minor}-${patch_n}"
		wget -O "${build_srcdir}-patches/$patch_n" "$url"
		patch \
			--directory="${build_srcdir}" \
			--input="${build_srcdir}-patches/$patch_n" \
			--strip=0
	done
	
	cd "${build_srcdir}"

	./configure \
		--prefix="${SHVR_DIR_OUT}/bash_${version}"

	make -j "$(nproc)"

	mkdir -p "${SHVR_DIR_OUT}/bash_${version}/bin"
	cp bash "${SHVR_DIR_OUT}/bash_${version}/bin/bash"

	"${SHVR_DIR_OUT}/bash_${version}/bin/bash" --version
}
