#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_loksh ()
{
	cat <<-@
		loksh_7.8
		loksh_7.7
	@
}

shvr_targets_loksh ()
{
	cat <<-@
		loksh_7.8
		loksh_7.7
		loksh_7.6
		loksh_7.5
		loksh_7.4
		loksh_7.3
		loksh_7.1
		loksh_7.0
		loksh_6.9
		loksh_6.8.1
		loksh_6.7.5
	@
}

shvr_versioninfo_loksh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/loksh/${version}"
}

shvr_download_loksh ()
{
	shvr_versioninfo_loksh "$1"

	mkdir -p "${SHVR_DIR_SRC}/loksh"

	if ! test -f "${build_srcdir}.tar.xz"
	then
		wget -O "${build_srcdir}.tar.xz" \
			"https://github.com/dimkr/loksh/releases/download/$version/loksh-$version.tar.xz"
	fi
}

shvr_build_loksh ()
{
	shvr_versioninfo_loksh "$1"

	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc meson ninja-build xz-utils

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
