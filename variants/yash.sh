#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_yash ()
{
	shvr_cache targets_yash \
		curl --no-progress-meter https://api.github.com/repos/magicant/yash/releases |
			sed -n '
				/^    "tag_name": "/ {
					s/^    "tag_name": "/yash_/
					s/",$//
					p
				}
			' |
			sort -u |
			sort -V -r
}

shvr_majors_yash () { shvr_semver_majors yash; }
shvr_minors_yash () { shvr_semver_minors yash "$@"; }
shvr_patches_yash () { shvr_semver_patches yash "$@"; }

shvr_build_yash ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/yash/${version}"
	mkdir -p "${build_srcdir}"
	
	apt-get -y install \
		wget gcc make xz-utils
	wget -O "${build_srcdir}.tar.gz" \
		"https://github.com/magicant/yash/releases/download/${version}/yash-${version}.tar.xz"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	./configure \
		--disable-nls \
		--disable-lineedit \
		--prefix="${SHVR_DIR_OUT}/yash_$version"

	make -j "$(nproc)"

	mkdir -p "${SHVR_DIR_OUT}/yash_${version}/bin"
	cp "yash" "${SHVR_DIR_OUT}/yash_$version/bin"
	
	"${SHVR_DIR_OUT}/yash_${version}/bin/yash" -c "echo yash version $version"
}
