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

		# Reproducible environment for toolchain build
		export SOURCE_DATE_EPOCH=1
		export TZ=UTC
		export LC_ALL=C
		export LANG=C

		cat > config.mak << MCMEOF
TARGET = ${SHVR_MCM_TARGET}
OUTPUT = ${SHVR_MCM_OUTPUT}
DL_CMD = curl -sSL -o
GNU_SITE = https://ftp.gnu.org/gnu
COMMON_CONFIG += CFLAGS_FOR_TARGET="-fno-asynchronous-unwind-tables -frandom-seed=1"
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

# Write build environment diagnostics to a log file for reproducibility debugging.
# Only writes the environment section once; subsequent calls are no-ops.
shvr_log_build_env ()
{
	log_file="${SHVR_DIR_OUT}/shvr/build-env.log"
	# Only write environment info once
	if test -f "$log_file"
	then
		return 0
	fi
	mkdir -p "$(dirname "$log_file")"
	(
		# Disable xtrace inside the log so it stays clean
		set +x
		echo "=== Build Environment ==="
		echo "--- uname -a ---"
		uname -a
		echo "--- /etc/os-release ---"
		cat /etc/os-release 2>/dev/null || echo "(not available)"
		echo "--- CPU model ---"
		grep -m1 'model name' /proc/cpuinfo 2>/dev/null || echo "(not available)"
		echo "--- CPU flags ---"
		grep -m1 '^flags' /proc/cpuinfo 2>/dev/null || echo "(not available)"
		echo "--- System GCC ---"
		gcc --version 2>/dev/null | head -1 || echo "(not installed)"
		echo "--- Cross-compiler GCC ---"
		"${SHVR_MCM_OUTPUT}/bin/${SHVR_MCM_TARGET}-gcc" --version 2>/dev/null | head -1 || echo "(not available)"
		echo "--- Cross-compiler binary SHA256 ---"
		sha256sum "${SHVR_MCM_OUTPUT}/bin/${SHVR_MCM_TARGET}-gcc" 2>/dev/null || echo "(not available)"
		echo "--- Cross-compiler config (cc -v) ---"
		"${SHVR_MCM_OUTPUT}/bin/${SHVR_MCM_TARGET}-gcc" -v 2>&1 || echo "(not available)"
		echo "--- nproc ---"
		nproc 2>/dev/null || echo "(not available)"
	) > "$log_file" 2>&1
}
