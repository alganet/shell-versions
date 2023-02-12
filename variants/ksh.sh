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

shvr_build_ksh ()
{
	version="$1"
	fork_name="${1%%-*}"
	fork_version="${1#*-}"
	build_srcdir="${SHVR_DIR_SRC}/ksh/${version}"
	mkdir -p "${build_srcdir}"
	
	case "$fork_name" in
		'93u+m')
			apt-get -y install \
				wget gcc
			wget -O "${build_srcdir}.tar.gz" \
				"https://github.com/ksh93/ksh/archive/refs/tags/${fork_version}.tar.gz"
			;;
		'2020')
			apt-get -y install \
				wget gcc meson
			wget -O "${build_srcdir}.tar.gz" \
				"https://github.com/ksh2020/ksh/archive/refs/tags/${fork_version}.tar.gz"
			;;
		'history')
			apt-get -y install \
				wget gcc
			wget -O "${build_srcdir}.tar.gz" \
				"https://api.github.com/repos/ksh93/ksh93-history/tarball/${fork_version}"
			;;
	esac

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	if test -f "bin/package"
	then
		bin/package make

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		host_type="$(bin/package host type)"
		cp "arch/${host_type}/bin/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
		cp "arch/${host_type}/bin/shcomp" "${SHVR_DIR_OUT}/ksh_${version}/bin/shcomp"
	elif test -f "meson.build"
	then
		meson \
			--prefix="${SHVR_DIR_OUT}/ksh_$version" \
			build

		ninja -C build

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		cp "build/src/cmd/ksh93/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
		cp "build/src/cmd/ksh93/shcomp" "${SHVR_DIR_OUT}/ksh_${version}/bin/shcomp"
	fi
	
	"${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" -c "echo ksh version $version"
}
