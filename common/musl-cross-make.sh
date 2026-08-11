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

# The tarballs musl-cross-make's own Makefile would otherwise download DURING
# `make`, listed here so they are fetched, checksum-verified and CACHED like every
# other source in this project instead of being pulled from the network in the
# middle of a Docker RUN.
#
# That mid-build fetch was the project's largest unguarded network surface: ~146MB
# over seven requests, no retry, no timeout, and -- because musl-cross-make's
# DL_CMD lacked curl's -f -- an HTTP error page would be saved as the tarball and
# surface as a sha1 mismatch inside a parallel make log. `make` exits 2, and all
# the user sees is "did not complete successfully: exit code: 2".
#
# Versions are musl-cross-make's Makefile defaults for the pinned commit, except
# GCC_VER which config.mak below overrides. Keep the two in sync: if `make` ever
# tries to download something, this list is stale (see the DL_CMD note below).
SHVR_MCM_GCC_VER="13.3.0"
SHVR_MCM_BINUTILS_VER="2.44"
SHVR_MCM_MUSL_VER="1.2.5"
SHVR_MCM_GMP_VER="6.3.0"
SHVR_MCM_MPC_VER="1.3.1"
SHVR_MCM_MPFR_VER="4.2.2"
SHVR_MCM_LINUX_VER="headers-4.19.88-2"

# Where the pre-fetched tarballs live. Deliberately NOT "musl-cross-make-sources":
# the Dockerfile's `COPY "build/musl-cross-make-*"` glob would match a directory of
# that name and flatten its contents into the wrong place.
SHVR_MCM_SOURCES="musl-sources"

shvr_download_musl_sources ()
{
	ms_dir="${SHVR_DIR_SRC}/${SHVR_MCM_SOURCES}"
	mkdir -p "$ms_dir"

	# No `test -f` guard around these calls, deliberately. shvr_fetch already
	# skips the DOWNLOAD for a file that is present, but it still verifies it --
	# so calling it unconditionally means a tarball restored from the Actions
	# cache is checksum-checked on every run, where an outer guard would hand a
	# cached (possibly truncated, possibly poisoned) file straight to the build
	# unverified. That outer-guard pattern is what the rest of the repo does; it
	# is not worth copying here, where the cache is the normal path.

	# The five GNU tarballs, through the mirror list.
	for ms_spec in \
		"gcc/gcc-${SHVR_MCM_GCC_VER}/gcc-${SHVR_MCM_GCC_VER}.tar.xz" \
		"binutils/binutils-${SHVR_MCM_BINUTILS_VER}.tar.gz" \
		"gmp/gmp-${SHVR_MCM_GMP_VER}.tar.xz" \
		"mpc/mpc-${SHVR_MCM_MPC_VER}.tar.gz" \
		"mpfr/mpfr-${SHVR_MCM_MPFR_VER}.tar.xz"
	do
		shvr_fetch_mirrors "${ms_dir}/${ms_spec##*/}" $(shvr_gnu_mirrors "$ms_spec")
	done

	# musl and the kernel headers are not GNU-hosted; single origin, but both are
	# small and shvr_fetch now retries.
	shvr_fetch \
		"https://musl.libc.org/releases/musl-${SHVR_MCM_MUSL_VER}.tar.gz" \
		"${ms_dir}/musl-${SHVR_MCM_MUSL_VER}.tar.gz"

	shvr_fetch \
		"https://ftp.barfooze.de/pub/sabotage/tarballs/linux-${SHVR_MCM_LINUX_VER}.tar.xz" \
		"${ms_dir}/linux-${SHVR_MCM_LINUX_VER}.tar.xz"
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

	# Seed musl-cross-make's own sources/ with the tarballs we already fetched and
	# verified. It skips the download for any file already present, and still
	# checks each one against its committed hashes/*.sha1 -- so this adds our
	# sha256 on top of their sha1 rather than replacing a check with trust.
	# `dir/.` rather than `dir/*`: shvr.sh runs under `set -euf`, and -f disables
	# pathname expansion, so a glob here stays a literal asterisk and cp fails
	# with "cannot stat '.../musl-sources/*'".
	mkdir -p "${SHVR_DIR_SRC}/musl-cross-make/sources"
	if test -d "${SHVR_DIR_SRC}/${SHVR_MCM_SOURCES}"
	then
		cp -pR "${SHVR_DIR_SRC}/${SHVR_MCM_SOURCES}/." \
			"${SHVR_DIR_SRC}/musl-cross-make/sources/"
	fi

	(
		cd "${SHVR_DIR_SRC}/musl-cross-make" || exit 1
		# GNU_SITE is deliberately NOT set. musl-cross-make's own default is
		# https://ftpmirror.gnu.org/gnu -- GNU's official redirector across the
		# worldwide mirror network. This file used to override it with
		# https://ftp.gnu.org/gnu, the single canonical origin and the most
		# rate-limited host of the set: a downgrade, not a pin. Nothing here needs
		# a fixed origin, because every tarball is checksum-verified either way.
		#
		# DL_CMD should never fire now that sources/ is pre-seeded above. It is
		# kept, hardened, as the fallback for a cold cache -- and -f means that if
		# it ever does fire and fail, it says so instead of saving an error page for
		# the sha1 check to trip over three layers down. If you see it download
		# anything, SHVR_MCM_*_VER above has drifted from the pinned commit.
		cat > config.mak << MCMEOF
TARGET = ${SHVR_MCM_TARGET}
OUTPUT = ${SHVR_MCM_OUTPUT}
GCC_VER = ${SHVR_MCM_GCC_VER}
DL_CMD = curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 30 --max-time 1800 -o
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
