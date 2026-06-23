#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# Static GNU readline built with musl-cross against the in-tree static ncurses -
# pinned version for reproducible builds. Provides readline/readline.h +
# libreadline.a for shells that want full GNU readline line editing/history/
# completion (e.g. osh --readline).
#
# NOTE ON LICENSING: GNU readline is GPLv3. A binary that statically links this
# library is a GPLv3 combined work. It is provided here only for osh, whose
# interactive features require the full GNU readline API (libedit's readline
# compatibility layer is missing functions Oils calls); a binary built without it
# stays permissively licensed.
. "${SHVR_DIR_SELF}/common/ncurses.sh"

SHVR_READLINE_VERSION="8.3"
SHVR_READLINE_PREFIX="${SHVR_DIR_SRC}/readline/readline-${SHVR_READLINE_VERSION}-install"

shvr_download_readline ()
{
	mkdir -p "${SHVR_DIR_SRC}/readline"

	if ! test -f "${SHVR_DIR_SRC}/readline/readline-${SHVR_READLINE_VERSION}.tar.gz"
	then
		shvr_fetch \
			"https://ftp.gnu.org/gnu/readline/readline-${SHVR_READLINE_VERSION}.tar.gz" \
			"${SHVR_DIR_SRC}/readline/readline-${SHVR_READLINE_VERSION}.tar.gz"
	fi

	# readline links the terminal library; it uses our in-tree static ncurses.
	shvr_download_ncurses
}

shvr_build_readline ()
{
	if test -f "${SHVR_READLINE_PREFIX}/lib/libreadline.a" &&
		test -f "${SHVR_READLINE_PREFIX}/.shvr-merged"
	then
		return 0
	fi

	# readline needs a termcap/terminfo library (tgetent); supply the in-tree one.
	shvr_build_ncurses

	readline_srcdir="${SHVR_DIR_SRC}/readline/readline-${SHVR_READLINE_VERSION}-src"
	mkdir -p "${readline_srcdir}"

	shvr_untar \
		"${SHVR_DIR_SRC}/readline/readline-${SHVR_READLINE_VERSION}.tar.gz" \
		"${readline_srcdir}"

	cd "${readline_srcdir}"

	SOURCE_DATE_EPOCH=1 \
	TZ=UTC \
	CC="$(shvr_musl_cc)" \
	AR="$(shvr_musl_ar)" \
	RANLIB="$(shvr_musl_ranlib)" \
	CFLAGS="-static -frandom-seed=1 $(shvr_ncurses_cflags)" \
	LDFLAGS="-Wl,--build-id=none $(shvr_ncurses_ldflags)" \
	./configure \
		--host="$(shvr_musl_target)" \
		--prefix="${SHVR_READLINE_PREFIX}" \
		--disable-shared \
		--enable-static \
		--with-curses

	make -j"$(nproc)"
	make install

	# Consumers (osh's detect/link) link a bare `-lreadline` with no `-lncurses`,
	# but libreadline.a references termcap symbols (tgetent...). Merge the in-tree
	# ncurses into libreadline.a so the static library is self-contained. ar -M
	# (MRI script) preserves all members from both archives; the cross ar/ranlib
	# are deterministic (musl-cross-make --enable-deterministic-archives).
	"$(shvr_musl_ar)" -M <<-MRI
		CREATE ${SHVR_READLINE_PREFIX}/lib/libreadline-merged.a
		ADDLIB ${SHVR_READLINE_PREFIX}/lib/libreadline.a
		ADDLIB ${SHVR_READLINE_PREFIX}/lib/libhistory.a
		ADDLIB ${SHVR_NCURSES_PREFIX}/lib/libncurses.a
		SAVE
		END
	MRI
	mv "${SHVR_READLINE_PREFIX}/lib/libreadline-merged.a" \
		"${SHVR_READLINE_PREFIX}/lib/libreadline.a"
	"$(shvr_musl_ranlib)" "${SHVR_READLINE_PREFIX}/lib/libreadline.a"
	touch "${SHVR_READLINE_PREFIX}/.shvr-merged"
}

shvr_readline_prefix ()
{
	echo "${SHVR_READLINE_PREFIX}"
}
