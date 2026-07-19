#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/ncurses.sh"
. "${SHVR_DIR_SELF}/common/patches.sh"

shvr_static_yash ()
{
	return 0
}

shvr_current_yash ()
{
	shvr_read_versions yash current
}

shvr_targets_yash ()
{
	shvr_read_versions yash all
}

shvr_update_yash ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/github_releases.sh"
	shvr_versions_from_github_tags magicant/yash '([0-9]+\.[0-9]+(\.[0-9]+)?)' |
		shvr_merge_versions yash
}

shvr_series_yash ()
{
	shvr_versioninfo_yash "$1" || return 1
	printf '%s.%s\n' "${version_major}" "${version_minor}"
}

# The branch the next yash accrues on. yash develops on trunk (not master/main), so that
# is where the next release begins to exist and what the snapshot tracks. This was
# deferred while the toolchain pinned gcc 9.4.0: trunk's common.h:57 uses __has_builtin in
# a bare #if, a gcc 10 preprocessor feature, so gcc 9 failed to parse it ("missing binary
# operator before token '('"). The toolchain now pins gcc 13.3.0 (common/musl-cross-make.sh),
# which parses it, so the channel is live.
shvr_snapshotsource_yash ()
{
	echo "https://github.com/magicant/yash trunk"
}

shvr_versioninfo_yash ()
{
	version="$1"

	# Before the numeric parsing below, which would reject the token (no "." in it, so
	# version_major would equal version -> return 1). yash's trunk ships its
	# hand-written ./configure, so the build needs nothing special.
	if shvr_is_snapshot "$version"
	then
		version_major=99
		version_minor=99
		version_patch=0
		build_srcdir="${SHVR_DIR_SRC}/yash/${version}"
		return 0
	fi

	version_major="${version%%\.*}"

	if test "$version" = "$version_major"
	then return 1
	fi
	version_minor="${version#$version_major\.}"
	version_patch="${version_minor#*\.}"
	if test "$version_patch" = "$version_minor"
	then version_patch="0"
	else version_minor="${version_minor%\.*}"
	fi

	build_srcdir="${SHVR_DIR_SRC}/yash/${version}"
}

shvr_download_yash ()
{
	shvr_versioninfo_yash "$1"

	mkdir -p "${SHVR_DIR_SRC}/yash"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		# Upstream publishes release tarballs only from 2.41 up (the
		# releases/download asset 404s at or below 2.40, and never existed for
		# the 1.x / 0.x line), but the git tag still resolves and its
		# auto-generated archive tarball ships the in-tree ./configure. 2.41+
		# keep the release tarball so their committed source checksums stay
		# valid; everything older fetches the archive tag tarball. Both URLs are
		# saved as .tar.gz (tar autodetects xz/gz).
		if shvr_is_snapshot "$version"
		then
			shvr_snapshot_fetch_git yash "$version" "${build_srcdir}.tar.gz" "yash-${version}"
		elif test "$version_major" -gt 2 ||
			{ test "$version_major" -eq 2 && test "$version_minor" -ge 41; }
		then
			shvr_fetch "https://github.com/magicant/yash/releases/download/${version}/yash-${version}.tar.xz" "${build_srcdir}.tar.gz"
		else
			shvr_fetch "https://github.com/magicant/yash/archive/refs/tags/${version}.tar.gz" "${build_srcdir}.tar.gz"
		fi
	fi

	# yash's built-in line editor needs a terminfo/curses library; we link the
	# in-tree static ncurses for it.
	shvr_download_ncurses
}

shvr_build_yash ()
{
	shvr_versioninfo_yash "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	shvr_apply_patches yash "$version"

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC="$(shvr_musl_cc) -static"
	export AR="$(shvr_musl_ar)"
	export RANLIB="$(shvr_musl_ranlib)"
	export CFLAGS="-frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"

	# Build the in-tree static ncurses and point yash at it so its built-in line
	# editor (emacs/vi modes, completion, history, multibyte display) is enabled.
	# yash's configure searches its default term_lib list and links the first that
	# satisfies a setupterm/tigetstr/tputs probe, so supplying the ncurses headers
	# and lib path is enough on every version; no --with-term-lib is needed (it
	# only exists >=2.19 and the older hand-written configure exits on unknown
	# options).
	#
	# These flags go in CADDS, not CFLAGS, for two reasons. (1) yash uses
	# ${CFLAGS-${cflags}}, so exporting CFLAGS would REPLACE yash's own computed
	# cflags, and after its -O2 probe it rewrites cflags to a bare "-O2 -g" anyway,
	# dropping any CFLAGS-based -I from the probes; CADDS is always appended and is
	# never clobbered. (2) -DHAVE_CONFIG_H makes the build include config.h, which
	# is where yash >=2.19 records HAVE_CURSES_H / HAVE_TERM_H; without it those
	# versions' lineedit/terminfo.c fails to compile ("cur_term undeclared")
	# because its curses/term includes are guarded on those macros. The musl
	# <wchar.h> iswdigit-macro clash in arith.c that config.h's feature macros
	# would expose is already handled by patches/yash/*/*arith-c-include-wctype*.
	shvr_build_ncurses
	cd "${build_srcdir}"
	export CADDS="$(shvr_ncurses_cflags) -DHAVE_CONFIG_H"
	export LDFLAGS="${LDFLAGS} $(shvr_ncurses_ldflags)"

	# Older yash (<2.26) has no NLS feature, so its hand-written configure
	# rejects --disable-nls as an unknown feature ("invalid option"). Pass it
	# only when this configure actually knows the option. NLS stays off either
	# way: musl provides no libintl.
	nls_flag=
	if grep -qE '^[[:space:]]*nls\)' configure
	then nls_flag=--disable-nls
	fi

	./configure \
		$nls_flag \
		--prefix="${SHVR_DIR_OUT}/yash_$version"

	# Default target is `all: yash depends`, where `depends` reruns the
	# freshly-linked binary's `makedepend` builtin to refresh dev-time
	# dependency lines. On 2.7 that builtin exits non-zero and aborts `make`,
	# even though the `yash` binary is already fully linked; building the
	# `yash` target directly skips the dev-only depends step. The produced
	# binary is identical (depends never relinks it), so this is byte-neutral
	# for the versions that don't need it -- but it is only required for 2.7.
	case "$version" in
	2.7) make yash ;;
	*)   make ;;
	esac

	unset SOURCE_DATE_EPOCH TZ CC AR RANLIB CFLAGS CADDS LDFLAGS

	mkdir -p "${SHVR_DIR_OUT}/yash_${version}/bin"
	cp "yash" "${SHVR_DIR_OUT}/yash_$version/bin"

	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/yash_${version}/bin/yash"
	touch -d "@1" "${SHVR_DIR_OUT}/yash_${version}/bin/yash"
	chmod 755 "${SHVR_DIR_OUT}/yash_${version}/bin/yash"

	"${SHVR_DIR_OUT}/yash_${version}/bin/yash" -c "echo yash version $version"
}

shvr_deps_yash ()
{
	shvr_versioninfo_yash "$1"
	apt-get -y install \
		curl make xz-utils gettext patch
}
