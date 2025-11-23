#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_busybox ()
{
	cat <<-@
		busybox_1.37.0
		busybox_1.36.1
	@
}

shvr_targets_busybox ()
{
	cat <<-@
		busybox_1.37.0
		busybox_1.36.1
		busybox_1.35.0
		busybox_1.34.1
		busybox_1.33.2
		busybox_1.32.1
		busybox_1.31.1
		busybox_1.30.1
		busybox_1.29.3
		busybox_1.28.4
		busybox_1.27.2
		busybox_1.26.2
		busybox_1.25.1
	@
}

shvr_versioninfo_busybox ()
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
	build_srcdir="${SHVR_DIR_SRC}/busybox/${version}"
}

shvr_download_busybox ()
{
	shvr_versioninfo_busybox "$1"

	mkdir -p "${SHVR_DIR_SRC}/busybox"

	if ! test -f "${build_srcdir}.tar.bz2"
	then
		shvr_fetch "https://busybox.net/downloads/busybox-${version}.tar.bz2" "${build_srcdir}.tar.bz2"
	fi
}
