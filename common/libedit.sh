#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# Static libedit (the BSD editline line editor) built with musl-cross against the
# in-tree static ncurses - pinned version for reproducible builds. Provides
# histedit.h + libedit.a for shells that want BSD-licensed line editing/history
# (e.g. dash --with-libedit).
. "${SHVR_DIR_SELF}/common/ncurses.sh"

SHVR_LIBEDIT_VERSION="20260512-3.1"
SHVR_LIBEDIT_PREFIX="${SHVR_DIR_SRC}/libedit/libedit-${SHVR_LIBEDIT_VERSION}-install"

shvr_download_libedit ()
{
	mkdir -p "${SHVR_DIR_SRC}/libedit"

	if ! test -f "${SHVR_DIR_SRC}/libedit/libedit-${SHVR_LIBEDIT_VERSION}.tar.gz"
	then
		shvr_fetch \
			"https://thrysoee.dk/editline/libedit-${SHVR_LIBEDIT_VERSION}.tar.gz" \
			"${SHVR_DIR_SRC}/libedit/libedit-${SHVR_LIBEDIT_VERSION}.tar.gz"
	fi

	# libedit links the terminal library; it uses our in-tree static ncurses.
	shvr_download_ncurses
}

shvr_build_libedit ()
{
	if test -f "${SHVR_LIBEDIT_PREFIX}/lib/libedit.a"
	then
		return 0
	fi

	# libedit needs a termcap/terminfo library (tgetent); supply the in-tree one.
	shvr_build_ncurses

	libedit_srcdir="${SHVR_DIR_SRC}/libedit/libedit-${SHVR_LIBEDIT_VERSION}-src"
	mkdir -p "${libedit_srcdir}"

	shvr_untar \
		"${SHVR_DIR_SRC}/libedit/libedit-${SHVR_LIBEDIT_VERSION}.tar.gz" \
		"${libedit_srcdir}"

	cd "${libedit_srcdir}"

	SOURCE_DATE_EPOCH=1 \
	TZ=UTC \
	CC="$(shvr_musl_cc)" \
	AR="$(shvr_musl_ar)" \
	RANLIB="$(shvr_musl_ranlib)" \
	CFLAGS="-static -frandom-seed=1 $(shvr_ncurses_cflags)" \
	LDFLAGS="-Wl,--build-id=none $(shvr_ncurses_ldflags)" \
	./configure \
		--host="$(shvr_musl_target)" \
		--prefix="${SHVR_LIBEDIT_PREFIX}" \
		--disable-shared \
		--enable-static

	make -j"$(nproc)"
	make install
}

shvr_libedit_cflags ()
{
	echo "-I${SHVR_LIBEDIT_PREFIX}/include"
}

shvr_libedit_ldflags ()
{
	echo "-L${SHVR_LIBEDIT_PREFIX}/lib"
}
