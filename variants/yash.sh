#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/ncurses.sh"

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

shvr_versioninfo_yash ()
{
	version="$1"
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
		# Upstream stopped publishing release tarballs at or below 2.40 (the
		# releases/download asset 404s), but the git tag still resolves and
		# its auto-generated archive tarball ships the in-tree ./configure.
		# 2.41+ keep the release tarball so their committed source checksums
		# stay valid. Both URLs are saved as .tar.gz (tar autodetects xz/gz).
		if test "$version_major" -eq 2 && test "$version_minor" -le 40
		then
			shvr_fetch "https://github.com/magicant/yash/archive/refs/tags/${version}.tar.gz" "${build_srcdir}.tar.gz"
		else
			shvr_fetch "https://github.com/magicant/yash/releases/download/${version}/yash-${version}.tar.xz" "${build_srcdir}.tar.gz"
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

	if test -d "${SHVR_DIR_SELF}/patches/yash/$version"
	then
		find "${SHVR_DIR_SELF}/patches/yash/$version" -type f -o -type l | sort | while read -r patch_file
		do patch -p0 < "$patch_file"
		done
	fi

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

	make

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
