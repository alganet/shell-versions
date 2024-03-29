#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_mrsh ()
{
	cat <<-@
	@
}

shvr_majors_mrsh () { shvr_semver_majors mrsh; }
shvr_minors_mrsh () { shvr_semver_minors mrsh "$@"; }
shvr_patches_mrsh () { shvr_semver_patches mrsh "$@"; }

shvr_build_mrsh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/mrsh/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc make
	wget -O "${build_srcdir}.tar.gz" \
		"https://api.github.com/repos/emersion/mrsh/tarball/${version}"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	./configure \
		--prefix="${SHVR_DIR_OUT}/mrsh_$version"

	make -j "$(nproc)"
	mkdir -p "${SHVR_DIR_OUT}/mrsh_${version}/bin"
	cp "./mrsh" "${SHVR_DIR_OUT}/mrsh_$version/bin"
	
	"${SHVR_DIR_OUT}/mrsh_${version}/bin/mrsh" -c "echo mrsh version $version"
}
