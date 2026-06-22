#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/rustup.sh"

shvr_current_brush ()
{
	shvr_read_versions brush current
}

shvr_targets_brush ()
{
	shvr_read_versions brush all
}

shvr_update_brush ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/github_releases.sh"
	shvr_versions_from_github_tags reubeno/brush 'brush-shell-v([0-9]+\.[0-9]+(\.[0-9]+)?)' |
		shvr_merge_versions brush
}

shvr_series_brush ()
{
	shvr_versioninfo_brush "$1" || return 1
	printf '%s.%s\n' "${version_major}" "${version_minor}"
}

shvr_versioninfo_brush ()
{
	version="$1"
	version_major="${version%%\.*}"

	if test "$version" = "$version_major"
	then return 1
	fi
	version_minor="${version#$version_major\.}"
	version_patch="${version_minor#*\.}"
	if test "$version_patch" = "$version_minor"
	then version_patch="0"
	else version_minor="${version_minor%\.*}"
	fi

	build_srcdir="${SHVR_DIR_SRC}/brush/${version}"
}

shvr_download_brush ()
{
	shvr_versioninfo_brush "$1"

	shvr_download_rustup

	mkdir -p "${SHVR_DIR_SRC}/brush"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://github.com/reubeno/brush/archive/refs/tags/brush-shell-v${version}.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_static_brush ()
{
	return 0
}

shvr_build_brush ()
{
	. "$HOME/.cargo/env"

	shvr_versioninfo_brush "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	# Static musl build with reproducible flags. The linker is pinned to
	# musl-cross-make's cross-gcc so the resulting bytes are independent of
	# the build host's stock cc (which on a non-x86_64 host can't produce
	# x86_64 binaries at all, and on x86_64 differs across distros).
	rust_target="$(shvr_rust_target)"
	cargo_env="$(echo "$rust_target" | tr 'a-z-' 'A-Z_')"
	cc_env="$(echo "$rust_target" | tr '-' '_')"

	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	eval "export CARGO_TARGET_${cargo_env}_LINKER=\"\$(shvr_musl_cc)\""
	eval "export CC_${cc_env}=\"\$(shvr_musl_cc)\""
	export RUSTFLAGS="-A unused_imports -C target-feature=+crt-static -C link-arg=-Wl,--build-id=none"

	cargo build --release --target "$rust_target"

	eval "unset CARGO_TARGET_${cargo_env}_LINKER CC_${cc_env}"
	unset SOURCE_DATE_EPOCH TZ RUSTFLAGS

	mkdir -p "${SHVR_DIR_OUT}/brush_${version}/bin"
	cp "./target/${rust_target}/release/brush" "${SHVR_DIR_OUT}/brush_$version/bin"

	# Strip binary to ensure reproducible output, using the cross-toolchain's
	# strip so the symbol-table layout is independent of the build host.
	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/brush_${version}/bin/brush"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/brush_${version}/bin/brush"
	chmod 755 "${SHVR_DIR_OUT}/brush_${version}/bin/brush"

	# Skip the smoke test on non-x86_64 build hosts; the cross-built binary
	# can only execute under an x86_64 host or a registered binfmt handler.
	if test "$(uname -m)" = "$(shvr_kernel_arch)"
	then "${SHVR_DIR_OUT}/brush_${version}/bin/brush" -c "echo brush version $version"
	else echo "skipping run-check on $(uname -m): cross-built $(shvr_musl_target) binary"
	fi
}

shvr_deps_brush ()
{
	shvr_versioninfo_brush "$1"
	apt-get -y install \
		curl gcc binutils

	if ! test -f "$HOME/.cargo/env"
	then
		shvr_download_rustup
		sh "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh" -y
	fi

	. "$HOME/.cargo/env"
	rustup target add "$(shvr_rust_target)"
}
