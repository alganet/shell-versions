#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/libedit.sh"

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

	# 0.5.2 predates musl compatibility on two fronts. (1) Its sources include
	# <sys/cdefs.h> (for the __P prototype macro), a glibc/BSD header musl does
	# not ship. (2) It uses the transitional LFS64 API (struct stat64, open64,
	# lseek64, ...) which musl 1.2.5 removed entirely, so those names are
	# undefined. A single compat shim handles both: it defines __P/__BEGIN_DECLS
	# and macro-maps every *64 name back to its base (musl is 64-bit-off_t
	# natively, so the remap is exact). The shim lives at <srcdir>/sys/cdefs.h so
	# the in-source `#include <sys/cdefs.h>` lines resolve via the Makefile's
	# `-I..`, and it is force-included through CPPFLAGS so files that use stat64
	# without including cdefs.h still get the mappings (configure overrides
	# CFLAGS with "-g -O2 -Wall" but keeps CPPFLAGS, which the compile applies).
	# 0.5.3+ dropped both the header include and the *64 API, so this is gated to
	# 0.5.2 only.
	case "$version" in
	0.5.2)
		mkdir -p "${build_srcdir}/sys"
		cat > "${build_srcdir}/sys/cdefs.h" <<-'CDEFS'
			#ifndef _SHVR_SYS_CDEFS_H
			#define _SHVR_SYS_CDEFS_H
			#ifndef __P
			#define __P(args) args
			#endif
			#ifndef __BEGIN_DECLS
			#define __BEGIN_DECLS
			#define __END_DECLS
			#endif
			/* musl 1.2.5 dropped the LFS64 transitional names; map them back. */
			#define stat64 stat
			#define lstat64 lstat
			#define fstat64 fstat
			#define open64 open
			#define creat64 creat
			#define lseek64 lseek
			#define off64_t off_t
			#define ino64_t ino_t
			#define blkcnt64_t blkcnt_t
			#define fsblkcnt64_t fsblkcnt_t
			#define fsfilcnt64_t fsfilcnt_t
			#define dirent64 dirent
			#define readdir64 readdir
			#ifndef O_LARGEFILE
			#define O_LARGEFILE 0
			#endif
			#endif
		CDEFS
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
		curl automake autoconf bison
}
