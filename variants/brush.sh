#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/rustup.sh"

shvr_current_brush ()
{
	cat <<-@
		brush_0.3.0
		brush_0.2.23
	@
}

shvr_targets_brush ()
{
	cat <<-@
		brush_0.3.0
		brush_0.2.23
	@
}

shvr_versioninfo_brush ()
{
	version="$1"
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

shvr_build_brush ()
{
	. "$HOME/.cargo/env"

	shvr_versioninfo_brush "$1"

	mkdir -p "${build_srcdir}"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	RUSTFLAGS="-A unused_imports" cargo build --release

	mkdir -p "${SHVR_DIR_OUT}/brush_${version}/bin"
	cp "./target/release/brush" "${SHVR_DIR_OUT}/brush_$version/bin"

	"${SHVR_DIR_OUT}/brush_${version}/bin/brush" -c "echo brush version $version"
}

shvr_deps_brush ()
{
	shvr_versioninfo_brush "$1"
	apt-get -y install \
		curl wget gcc

	if ! test -f "$HOME/.cargo/env"
	then
		shvr_download_rustup
		sh "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh" -y
	fi
}
