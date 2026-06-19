#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"

shvr_static_dash ()
{
	return 0
}

shvr_current_dash ()
{
	shvr_read_versions dash current
}

shvr_targets_dash ()
{
	shvr_read_versions dash all
}

shvr_update_dash ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/git_tags.sh"
	shvr_versions_from_git_tags \
		"https://git.kernel.org/pub/scm/utils/dash/dash.git" \
		'v([0-9.]+)' |
		shvr_merge_versions dash
}

shvr_series_dash ()
{
	shvr_versioninfo_dash "$1" || return 1
	case "$version" in
		*.*.*.*) printf '%s\n' "${version%.*}" ;;
		*)       printf '%s\n' "$version" ;;
	esac
}

shvr_versioninfo_dash ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/dash/${version}"
}

shvr_download_dash ()
{
	shvr_versioninfo_dash "$1"

	mkdir -p "${SHVR_DIR_SRC}/dash"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-$version.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_dash ()
{
	shvr_versioninfo_dash "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	if test -f ./autogen.sh
	then
		./autogen.sh
	else
		aclocal
		autoheader
		automake --add-missing
		autoconf
	fi

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC="$(shvr_musl_cc) -static"
	export AR="$(shvr_musl_ar)"
	export RANLIB="$(shvr_musl_ranlib)"
	export CFLAGS="-frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"

	./configure \
		--host=x86_64-linux-musl \
		--prefix="${SHVR_DIR_OUT}/dash_$version"

	make

	unset SOURCE_DATE_EPOCH TZ CC AR RANLIB CFLAGS LDFLAGS

	mkdir -p "${SHVR_DIR_OUT}/dash_${version}/bin"
	cp "src/dash" "${SHVR_DIR_OUT}/dash_$version/bin/dash"

	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/dash_${version}/bin/dash"
	touch -d "@1" "${SHVR_DIR_OUT}/dash_${version}/bin/dash"
	chmod 755 "${SHVR_DIR_OUT}/dash_${version}/bin/dash"

	"${SHVR_DIR_OUT}/dash_${version}/bin/dash" -c "echo dash version $version"
}

shvr_deps_dash ()
{
	shvr_versioninfo_dash "$1"
	# bison provides the yacc that dash <=0.5.5 needs to generate src/arith.c
	# from arith.y (AC_PROG_YACC picks "bison -y"); pre-generated in newer dash.
	apt-get -y install \
		curl automake autoconf bison
}
