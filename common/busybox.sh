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

shvr_snapshot_busybox ()
{
	shvr_read_versions busybox snapshot
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

# busybox develops on master. Note ash and hush both derive this channel (they carry no
# versions of their own), so versions/busybox.snapshot drives both their tags.
shvr_snapshotsource_busybox ()
{
	echo "https://git.busybox.net/busybox master"
}

shvr_versioninfo_busybox ()
{
	version="$1"

	# Before the numeric parsing below, which would reject the token (no "." in it).
	# busybox is kconfig-built (make allnoconfig), so the git tree needs no bootstrap;
	# the infinite version selects the modern path in the ash/hush recipes.
	if shvr_is_snapshot "$version"
	then
		version_major=99
		version_minor=99
		version_patch=0
		build_srcdir="${SHVR_DIR_SRC}/busybox/${version}"
		return 0
	fi

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
		# busybox does publish snapshot archives, but they are pinned by DATE, not sha,
		# and only ~31 days are kept. Naming a target snapshot-<sha> while fetching a
		# dated tarball whose content need not match that sha would be a lie, so the
		# lane clones like every other, keeping the token honest and uniform.
		if shvr_is_snapshot "$version"
		then shvr_snapshot_fetch_git busybox "$version" "${build_srcdir}.tar.bz2" "busybox-${version}"
		else shvr_fetch "https://busybox.net/downloads/busybox-${version}.tar.bz2" "${build_srcdir}.tar.bz2"
		fi
	fi
}

