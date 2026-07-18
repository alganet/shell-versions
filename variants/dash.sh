#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/libedit.sh"
. "${SHVR_DIR_SELF}/common/patches.sh"

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

# dash has a single line of development; master is what becomes the next release.
shvr_snapshotsource_dash ()
{
	echo "https://git.kernel.org/pub/scm/utils/dash/dash.git master"
}

# No version gates to fool here: dash's build keys off the whole token
# (`case "$version" in 0.5.2|0.5.3)`), which a snapshot misses, so it takes the modern
# path -- libedit, and ./autogen.sh, which the git tree ships. So the snapshot token
# needs nothing special beyond the build_srcdir every version already gets.
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
		if shvr_is_snapshot "$version"
		then shvr_snapshot_fetch_git dash "$version" "${build_srcdir}.tar.gz" "dash-${version}"
		else shvr_fetch "https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-$version.tar.gz" "${build_srcdir}.tar.gz"
		fi
	fi

	# >=0.5.4 builds with the in-tree libedit for line editing/history.
	# 0.5.2/0.5.3 predate --with-libedit (0.5.3 hardcodes -DSMALL) and must not
	# pull it in.
	case "$version" in
	0.5.2|0.5.3) ;;
	*)           shvr_download_libedit ;;
	esac
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
		# --foreign: pre-0.5.3 trees (e.g. 0.5.2) ship no AUTHORS/NEWS/README,
		# which GNU-strictness automake demands; foreign mode skips that check.
		# Harmless on versions that do carry the files.
		aclocal
		autoheader
		automake --foreign --add-missing
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

	# Interactive line editing + history via libedit. dash gained --with-libedit
	# at 0.5.4 (0.5.3 has no such option and hardcodes -DSMALL), and its configure
	# AC_MSG_ERRORs if the flag is passed without the library, so we build the
	# in-tree static libedit and pass the flag only for >=0.5.4. libedit needs a
	# termcap implementation (tgetent) from the in-tree ncurses, linked AFTER
	# -ledit; dash's configure appends "-ledit" last (LIBS="-lncurses -ledit"),
	# which is the wrong static link order, so reorder it in the generated Makefile.
	libedit_flag=
	case "$version" in
	0.5.2|0.5.3) ;;
	*)
		shvr_build_libedit
		cd "${build_srcdir}"
		libedit_flag="--with-libedit"
		export CFLAGS="${CFLAGS} $(shvr_libedit_cflags)"
		export LDFLAGS="${LDFLAGS} $(shvr_libedit_ldflags) $(shvr_ncurses_ldflags)"
		export LIBS="-lncurses"
		;;
	esac

	# The sys/cdefs.h musl shim that 0.5.2 needs is a patch now (see
	# patches/dash/sys-cdefs-musl-shim.diff for why). The patch is only half the
	# fix: files that use stat64 without including cdefs.h still need the
	# mappings, so the shim is also force-included. configure overrides CFLAGS
	# with "-g -O2 -Wall" but leaves CPPFLAGS alone, which the compile applies.
	shvr_apply_patches dash "$version"

	case "$version" in
	0.5.2)
		export CPPFLAGS="-include ${build_srcdir}/sys/cdefs.h"
		;;
	esac

	./configure \
		--host="$(shvr_musl_target)" \
		$libedit_flag \
		--prefix="${SHVR_DIR_OUT}/dash_$version"

	if test -n "$libedit_flag"
	then sed -i 's/-lncurses -ledit/-ledit -lncurses/' src/Makefile
	fi

	make

	unset SOURCE_DATE_EPOCH TZ CC AR RANLIB CFLAGS LDFLAGS LIBS CPPFLAGS

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
		curl patch automake autoconf bison
}
