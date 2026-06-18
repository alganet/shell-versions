#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/ncurses.sh"

# oksh >= 7.9 dropped the NO_CURSES build guard and unconditionally needs a
# curses library, so those versions link our static musl ncurses instead of
# building with --disable-curses. Requires shvr_versioninfo_oksh to have run.
shvr_oksh_needs_curses ()
{
	test "$version_major" -gt 7 ||
	{ test "$version_major" -eq 7 && test "$version_minor" -ge 9; }
}

shvr_static_oksh ()
{
	return 0
}

shvr_current_oksh ()
{
	shvr_read_versions oksh current
}

shvr_targets_oksh ()
{
	shvr_read_versions oksh all
}

shvr_update_oksh ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/github_releases.sh"
	shvr_versions_from_github_tags ibara/oksh 'oksh-([0-9.]+)' |
		shvr_merge_versions oksh
}

shvr_series_oksh ()
{
	shvr_versioninfo_oksh "$1" || return 1
	printf '%s.%s\n' "${version_major}" "${version_minor}"
}

shvr_versioninfo_oksh ()
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

	build_srcdir="${SHVR_DIR_SRC}/oksh/${version}"
}

shvr_download_oksh ()
{
	shvr_versioninfo_oksh "$1"

	mkdir -p "${SHVR_DIR_SRC}/oksh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://github.com/ibara/oksh/releases/download/oksh-$version/oksh-$version.tar.gz" "${build_srcdir}.tar.gz"
	fi

	if shvr_oksh_needs_curses
	then
		shvr_download_ncurses
	fi
}

shvr_build_oksh ()
{
	shvr_versioninfo_oksh "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC="$(shvr_musl_cc) -static"
	export AR="$(shvr_musl_ar)"
	export RANLIB="$(shvr_musl_ranlib)"
	export CFLAGS="-frandom-seed=1 -fcommon"
	export LDFLAGS="-Wl,--build-id=none"

	if {
		test "$version_major" -eq 7 &&
		test "$version_minor" -lt 3
	} || {
		test "$version_major" -lt 7
	}
	then
		export CFLAGS="-fcommon -frandom-seed=1"
	fi

	if shvr_oksh_needs_curses
	then
		shvr_build_ncurses
		cd "${build_srcdir}"
		export CFLAGS="${CFLAGS} $(shvr_ncurses_cflags)"
		export LDFLAGS="${LDFLAGS} $(shvr_ncurses_ldflags)"

		./configure \
			--prefix="${SHVR_DIR_OUT}/oksh_$version"
	else
		./configure \
			--disable-curses \
			--prefix="${SHVR_DIR_OUT}/oksh_$version"
	fi

	make

	unset SOURCE_DATE_EPOCH TZ CC AR RANLIB CFLAGS LDFLAGS

	mkdir -p "${SHVR_DIR_OUT}/oksh_${version}/bin"
	cp "oksh" "${SHVR_DIR_OUT}/oksh_$version/bin"

	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/oksh_${version}/bin/oksh"
	touch -d "@1" "${SHVR_DIR_OUT}/oksh_${version}/bin/oksh"
	chmod 755 "${SHVR_DIR_OUT}/oksh_${version}/bin/oksh"

	"${SHVR_DIR_OUT}/oksh_${version}/bin/oksh" -c "echo oksh version $version"
}

shvr_deps_oksh ()
{
	shvr_versioninfo_oksh "$1"
	apt-get -y install \
		curl make
}
