#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# Static ncurses built with musl-cross-make - pinned version for reproducible builds
SHVR_NCURSES_VERSION="6.5"
SHVR_NCURSES_PREFIX="${SHVR_DIR_SRC}/ncurses/ncurses-${SHVR_NCURSES_VERSION}-install"

shvr_download_ncurses ()
{
	mkdir -p "${SHVR_DIR_SRC}/ncurses"

	if ! test -f "${SHVR_DIR_SRC}/ncurses/ncurses-${SHVR_NCURSES_VERSION}.tar.gz"
	then
		shvr_fetch \
			"https://ftp.gnu.org/gnu/ncurses/ncurses-${SHVR_NCURSES_VERSION}.tar.gz" \
			"${SHVR_DIR_SRC}/ncurses/ncurses-${SHVR_NCURSES_VERSION}.tar.gz"
	fi
}

shvr_build_ncurses ()
{
	if test -f "${SHVR_NCURSES_PREFIX}/lib/libncurses.a"
	then
		return 0
	fi

	ncurses_srcdir="${SHVR_DIR_SRC}/ncurses/ncurses-${SHVR_NCURSES_VERSION}-src"
	mkdir -p "${ncurses_srcdir}"

	shvr_untar \
		"${SHVR_DIR_SRC}/ncurses/ncurses-${SHVR_NCURSES_VERSION}.tar.gz" \
		"${ncurses_srcdir}"

	cd "${ncurses_srcdir}"

	CC="$(shvr_musl_cc)" \
	AR="$(shvr_musl_ar)" \
	RANLIB="$(shvr_musl_ranlib)" \
	CFLAGS="-static -frandom-seed=1" \
	./configure \
		--host=x86_64-linux-musl \
		--prefix="${SHVR_NCURSES_PREFIX}" \
		--without-shared \
		--without-debug \
		--without-cxx \
		--without-cxx-binding \
		--without-ada \
		--without-manpages \
		--without-tests \
		--without-progs \
		--disable-widec \
		--enable-termcap \
		--with-default-terminfo-dir=/usr/share/terminfo \
		--with-pkg-config=no

	make -j"$(nproc)"
	make install
}

shvr_ncurses_cflags ()
{
	echo "-I${SHVR_NCURSES_PREFIX}/include -I${SHVR_NCURSES_PREFIX}/include/ncurses"
}

shvr_ncurses_ldflags ()
{
	echo "-L${SHVR_NCURSES_PREFIX}/lib"
}
