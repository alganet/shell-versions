#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# musl-cross-make toolchain - pinned versions for reproducible builds
SHVR_MCM_COMMIT="e5147dde912478dd32ad42a25003e82d4f5733aa"
SHVR_MCM_TARGET="x86_64-linux-musl"
SHVR_MCM_OUTPUT="/usr/local/musl-cross"

shvr_download_musl_cross_make ()
{
	if ! test -f "${SHVR_DIR_SRC}/musl-cross-make-${SHVR_MCM_COMMIT}.tar.gz"
	then
		shvr_fetch \
			"https://github.com/richfelker/musl-cross-make/archive/${SHVR_MCM_COMMIT}.tar.gz" \
			"${SHVR_DIR_SRC}/musl-cross-make-${SHVR_MCM_COMMIT}.tar.gz"
	fi
}

shvr_build_musl_cross_make ()
{
	# Skip if already built
	if test -x "${SHVR_MCM_OUTPUT}/bin/${SHVR_MCM_TARGET}-gcc"
	then
		return 0
	fi

	rm -Rf "${SHVR_DIR_SRC}/musl-cross-make"
	mkdir -p "${SHVR_DIR_SRC}/musl-cross-make"

	shvr_untar \
		"${SHVR_DIR_SRC}/musl-cross-make-${SHVR_MCM_COMMIT}.tar.gz" \
		"${SHVR_DIR_SRC}/musl-cross-make"

	(
		cd "${SHVR_DIR_SRC}/musl-cross-make" || exit 1
		cat > config.mak << MCMEOF
TARGET = ${SHVR_MCM_TARGET}
OUTPUT = ${SHVR_MCM_OUTPUT}
DL_CMD = curl -sSL -o
GNU_SITE = https://ftp.gnu.org/gnu
MCMEOF
		make -j"$(nproc)"
		make install
	)
}

shvr_musl_cc ()
{
	echo "${SHVR_MCM_OUTPUT}/bin/${SHVR_MCM_TARGET}-gcc"
}

shvr_musl_strip ()
{
	echo "${SHVR_MCM_OUTPUT}/bin/${SHVR_MCM_TARGET}-strip"
}

shvr_musl_ar ()
{
	echo "${SHVR_MCM_OUTPUT}/bin/${SHVR_MCM_TARGET}-ar"
}

shvr_musl_ranlib ()
{
	echo "${SHVR_MCM_OUTPUT}/bin/${SHVR_MCM_TARGET}-ranlib"
}
