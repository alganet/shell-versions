#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# Static PCRE libraries built with musl-cross - pinned versions for reproducible
# builds. zsh's optional `pcre` module needs one of these: zsh 5.0..5.8 use the
# original PCRE (libpcre / pcre-config), zsh 5.9+ use PCRE2 (libpcre2 /
# pcre2-config). Both install a *-config script that zsh's configure runs to get
# the cflags/libs. PCRE (original) is end-of-life (last release 8.45, 2021) and is
# carried only for those older zsh versions.

SHVR_PCRE1_VERSION="8.45"
SHVR_PCRE1_PREFIX="${SHVR_DIR_SRC}/pcre/pcre-${SHVR_PCRE1_VERSION}-install"
SHVR_PCRE2_VERSION="10.47"
SHVR_PCRE2_PREFIX="${SHVR_DIR_SRC}/pcre2/pcre2-${SHVR_PCRE2_VERSION}-install"

shvr_download_pcre1 ()
{
	mkdir -p "${SHVR_DIR_SRC}/pcre"
	if ! test -f "${SHVR_DIR_SRC}/pcre/pcre-${SHVR_PCRE1_VERSION}.tar.gz"
	then
		shvr_fetch \
			"https://downloads.sourceforge.net/project/pcre/pcre/${SHVR_PCRE1_VERSION}/pcre-${SHVR_PCRE1_VERSION}.tar.gz" \
			"${SHVR_DIR_SRC}/pcre/pcre-${SHVR_PCRE1_VERSION}.tar.gz"
	fi
}

shvr_download_pcre2 ()
{
	mkdir -p "${SHVR_DIR_SRC}/pcre2"
	if ! test -f "${SHVR_DIR_SRC}/pcre2/pcre2-${SHVR_PCRE2_VERSION}.tar.gz"
	then
		shvr_fetch \
			"https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${SHVR_PCRE2_VERSION}/pcre2-${SHVR_PCRE2_VERSION}.tar.gz" \
			"${SHVR_DIR_SRC}/pcre2/pcre2-${SHVR_PCRE2_VERSION}.tar.gz"
	fi
}

shvr_build_pcre1 ()
{
	if test -f "${SHVR_PCRE1_PREFIX}/lib/libpcre.a"
	then
		return 0
	fi

	pcre1_srcdir="${SHVR_DIR_SRC}/pcre/pcre-${SHVR_PCRE1_VERSION}-src"
	mkdir -p "${pcre1_srcdir}"
	shvr_untar \
		"${SHVR_DIR_SRC}/pcre/pcre-${SHVR_PCRE1_VERSION}.tar.gz" \
		"${pcre1_srcdir}"

	cd "${pcre1_srcdir}"

	SOURCE_DATE_EPOCH=1 \
	TZ=UTC \
	CC="$(shvr_musl_cc)" \
	AR="$(shvr_musl_ar)" \
	RANLIB="$(shvr_musl_ranlib)" \
	CFLAGS="-static -frandom-seed=1" \
	LDFLAGS="-Wl,--build-id=none" \
	./configure \
		--host="$(shvr_musl_target)" \
		--prefix="${SHVR_PCRE1_PREFIX}" \
		--disable-shared \
		--enable-static \
		--enable-utf8 \
		--enable-unicode-properties \
		--disable-cpp

	make -j"$(nproc)"
	make install
}

shvr_build_pcre2 ()
{
	if test -f "${SHVR_PCRE2_PREFIX}/lib/libpcre2-8.a"
	then
		return 0
	fi

	pcre2_srcdir="${SHVR_DIR_SRC}/pcre2/pcre2-${SHVR_PCRE2_VERSION}-src"
	mkdir -p "${pcre2_srcdir}"
	shvr_untar \
		"${SHVR_DIR_SRC}/pcre2/pcre2-${SHVR_PCRE2_VERSION}.tar.gz" \
		"${pcre2_srcdir}"

	cd "${pcre2_srcdir}"

	SOURCE_DATE_EPOCH=1 \
	TZ=UTC \
	CC="$(shvr_musl_cc)" \
	AR="$(shvr_musl_ar)" \
	RANLIB="$(shvr_musl_ranlib)" \
	CFLAGS="-static -frandom-seed=1" \
	LDFLAGS="-Wl,--build-id=none" \
	./configure \
		--host="$(shvr_musl_target)" \
		--prefix="${SHVR_PCRE2_PREFIX}" \
		--disable-shared \
		--enable-static \
		--enable-pcre2-8 \
		--enable-unicode

	make -j"$(nproc)"
	make install
}

# Path to the *-config script zsh's configure runs (added to PATH / PCRE_CONFIG).
shvr_pcre1_config ()
{
	echo "${SHVR_PCRE1_PREFIX}/bin/pcre-config"
}

shvr_pcre2_config ()
{
	echo "${SHVR_PCRE2_PREFIX}/bin/pcre2-config"
}
