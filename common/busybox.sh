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

# Source fixups for the 1.3..1.18 band (run after extraction, before the first
# make). Three musl/toolchain breaks live here -- the GNU make >= 4.3 mixed-rules
# Makefile error, include/platform.h's pre-stdint type fallbacks, and the
# __GLIBC__-gated fdprintf macro; see each block below. The whole helper is gated
# to 1.3 <= version <= 1.18: that band is either newly recovered or still
# excluded (no committed build checksums), whereas the buildable 1.2.x island
# (which carries the platform.h patterns but compiles fine as-is) and the
# already-building >=1.19 trees DO have committed checksums and must stay
# byte-identical -- so they are deliberately left untouched rather than relying
# on the seds happening to no-op.
shvr_busybox_fix_makefile ()
{
	# version_major/version_minor are set by shvr_versioninfo_busybox before the
	# build calls this. Only the 1.3..1.18 band needs (and may receive) the edits.
	if ! { test "${version_major:-0}" -eq 1 &&
		test "${version_minor:-0}" -ge 3 &&
		test "${version_minor:-0}" -le 18; }
	then return 0
	fi

	# Make the top-level Makefile parse under GNU make >= 4.3. The pre-kbuild-
	# 2.6.36 era inherits two kernel kbuild rules that put a normal target and a
	# pattern target on the same line -- `config %config:` and `/ %/:` -- which
	# make 4.3 rejects as a hard error ("mixed implicit and normal rules"), so the
	# build never reaches allnoconfig. We only ever invoke `allnoconfig` /
	# `oldconfig` (both match `%config`) and never build kernel modules (`%/`), so
	# dropping the bare normal target from each rule keeps every target we use.
	if test -f Makefile
	then
		sed -i \
			-e 's/^config %config:/%config:/' \
			-e 's,^/ %/:,%/:,' \
			Makefile
	fi

	# include/platform.h (1.3..1.16 era) only recognises glibc/uClibc/dietlibc/
	# newlib as "known" libcs; musl defines no libc-identity macro, so the header
	# falls into its fallback branch and hand-declares intmax_t/uintmax_t and
	# socklen_t -- which then conflict with musl's <stdint.h>/<sys/socket.h>
	# ("conflicting types"). Two surgical edits: force the known-libc branch
	# (always include <stdint.h>, which musl ships, instead of typedef'ing), and
	# rename the fallback `typedef int socklen_t;` (musl already provides the
	# type; the guard macro it keys off -- __socklen_t_defined -- varies by
	# version, but the typedef line itself is constant). Both match only the old
	# text, so they no-op on the musl-aware newer trees and the 1.2.x island --
	# byte-neutral there.
	if test -f include/platform.h
	then
		sed -i \
			-e 's/#if defined __GLIBC__ || defined __UCLIBC__/#if 1 || defined __GLIBC__ || defined __UCLIBC__/' \
			-e 's/^typedef int socklen_t;/typedef int socklen_t_shvr_unused;/' \
			include/platform.h
	fi

	# fdprintf: ash (and some applets) call fdprintf(), which busybox only maps to
	# the standard dprintf() under `#if defined(__GLIBC__)`. musl has dprintf but
	# no __GLIBC__, and the platform.c fallback is compiled out (HAVE_FDPRINTF is
	# defined by default), so the link fails with "undefined reference to
	# fdprintf" (the 1.16..1.18 break). Make that one guard unconditional so the
	# `# define fdprintf dprintf` always fires. Targets only the standalone
	# `#if defined(__GLIBC__)` line (not the `&& __GLIBC__ <= 2` version-check),
	# and no-ops on >=1.21 (which already define fdprintf unconditionally).
	if test -f include/platform.h
	then
		sed -i 's/^#if defined(__GLIBC__)$/#if 1/' include/platform.h
	fi
}
