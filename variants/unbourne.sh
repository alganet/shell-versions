#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_unbourne ()
{
	cat <<-@
	@
}

shvr_majors_unbourne () { shvr_semver_majors unbourne; }
shvr_minors_unbourne () { shvr_semver_minors unbourne "$@"; }
shvr_patches_unbourne () { shvr_semver_patches unbourne "$@"; }

shvr_build_unbourne ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/unbourne/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget
	wget -O "${build_srcdir}.tar.gz" \
		"https://github.com/jart/cosmopolitan/releases/download/${version}/cosmopolitan-${version}.tar.gz"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	cp build/bootstrap/ape.elf /usr/bin/ape

	build/bootstrap/make.com o//examples/unbourne.com
	mkdir -p "${SHVR_DIR_OUT}/unbourne_${version}/bin"
	cp "o//examples/unbourne.com" "${SHVR_DIR_OUT}/unbourne_$version/bin/unbourne"
	
	"${SHVR_DIR_OUT}/unbourne_${version}/bin/unbourne" -c "echo unbourne version $version"
}
