#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_busybox ()
{
	shvr_read_versions busybox current
}

shvr_targets_busybox ()
{
	shvr_read_versions busybox all
}

shvr_prerelease_busybox ()
{
	shvr_read_versions busybox prerelease
}

shvr_update_busybox ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/html_listing.sh"
	shvr_versions_from_html_listing \
		"https://busybox.net/downloads/" \
		'busybox-([0-9.]+)\.tar\.bz2' |
		shvr_merge_versions busybox
}

shvr_series_busybox ()
{
	shvr_versioninfo_busybox "$1" || return 1
	printf '%s.%s\n' "${version_major}" "${version_minor}"
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

