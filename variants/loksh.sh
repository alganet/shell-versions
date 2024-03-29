#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_loksh ()
{
	shvr_cache targets_loksh \
		curl --no-progress-meter https://api.github.com/repos/dimkr/loksh/releases |
			sed -n '
				/^    "tag_name": "/ {
					s/^    "tag_name": "/loksh_/
					s/",$//
					p
				}
			' |
			grep -v "^loksh_[5]\.[0-9]" |
			grep -v "^loksh_[6]\.[0-6]" |
			grep -v "^loksh_[6]\.7\.[0-4]$" |
			sort -u |
			sort -V -r
	return
}

shvr_majors_loksh () { shvr_semver_majors loksh; }
shvr_minors_loksh () { shvr_semver_minors loksh "$@"; }
shvr_patches_loksh () { shvr_semver_patches loksh "$@"; }

shvr_build_loksh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/loksh/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc meson ninja-build xz-utils
	wget -O "${build_srcdir}.tar.xz" \
		"https://github.com/dimkr/loksh/releases/download/$version/loksh-$version.tar.xz"

	tar --extract \
		--file="${build_srcdir}.tar.xz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	meson \
		--prefix="${SHVR_DIR_OUT}/loksh_$version" \
		build

	ninja -C build

	mkdir -p "${SHVR_DIR_OUT}/loksh_${version}/bin"
	cp "build/ksh" "${SHVR_DIR_OUT}/loksh_$version/bin/loksh"
	
	"${SHVR_DIR_OUT}/loksh_${version}/bin/loksh" -c "echo loksh version $version"
}
