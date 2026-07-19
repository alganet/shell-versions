#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# musl-cross-make toolchain - pinned versions for reproducible builds.
#
# GCC is pinned to 13.3.0 (config.mak below), overriding the musl-cross-make
# commit's own default of 9.4.0. gcc 9 lacks the __has_builtin preprocessor
# feature (added in gcc 10), which modern upstreams now use unguarded -- yash's
# trunk is the forcing case. The pinned commit already ships verified hashes for
# gcc 10.3.0..15.1.0, so this is a version pick, not a commit bump: the
# musl-cross-make tarball and its committed source checksum are unchanged.
SHVR_MCM_COMMIT="e5147dde912478dd32ad42a25003e82d4f5733aa"
SHVR_MCM_OUTPUT="/usr/local/musl-cross"

# Selected build architecture in OCI vocabulary (amd64|arm64). Defaults to amd64
# so the native x86_64 path is byte-for-byte unchanged. Every triple/cpu string
# below is derived from this, so SHVR_ARCH is the single knob.
SHVR_ARCH="${SHVR_ARCH:-amd64}"

shvr_arch ()
{
	case "${SHVR_ARCH}" in
		amd64|arm64) echo "${SHVR_ARCH}" ;;
		*) echo "shvr: unsupported SHVR_ARCH=${SHVR_ARCH}" >&2; return 1 ;;
	esac
}

shvr_musl_target ()
{
	case "$(shvr_arch)" in
		amd64) echo "x86_64-linux-musl" ;;
		arm64) echo "aarch64-linux-musl" ;;
	esac
}

shvr_rust_target ()
{
	case "$(shvr_arch)" in
		amd64) echo "x86_64-unknown-linux-musl" ;;
		arm64) echo "aarch64-unknown-linux-musl" ;;
	esac
}

shvr_meson_cpu ()
{
	case "$(shvr_arch)" in
		amd64) echo "x86_64" ;;
		arm64) echo "aarch64" ;;
	esac
}

shvr_kernel_arch ()
{
	case "$(shvr_arch)" in
		amd64) echo "x86_64" ;;
		arm64) echo "aarch64" ;;
	esac
}

SHVR_MCM_TARGET="$(shvr_musl_target)"

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
GCC_VER = 13.3.0
DL_CMD = curl -sSL -o
GNU_SITE = https://ftp.gnu.org/gnu
MCMEOF
		# Pin the parallelism to a FIXED value, not $(nproc). GCC's build is not
		# reproducible across different -j (parallel codegen ordering leaks into
		# the compiler binary), so building with the host's core count bakes the
		# host into the toolchain — and thus into every shell it compiles. A fixed
		# -j makes the toolchain (and all build checksums) byte-identical on any
		# Docker host. 4 matches the GitHub-hosted runner core count, so the
		# existing committed checksums are preserved.
		make -j4
		make install
	)
}

shvr_musl_cc ()
{
	echo "${SHVR_MCM_OUTPUT}/bin/${SHVR_MCM_TARGET}-gcc"
}

shvr_musl_cxx ()
{
	echo "${SHVR_MCM_OUTPUT}/bin/${SHVR_MCM_TARGET}-g++"
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
