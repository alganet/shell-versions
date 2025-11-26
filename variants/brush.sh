#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_brush ()
{
	cat <<-@
		brush_0.2.23
		brush_0.2.22
	@
}

shvr_targets_brush ()
{
	cat <<-@
		brush_0.2.23
		brush_0.2.22
		brush_0.2.21
		brush_0.2.20
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

	if ! test -f "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh"
	then
		shvr_fetch "https://raw.githubusercontent.com/rust-lang/rustup/refs/tags/1.28.2/rustup-init.sh" "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh"
	fi

	mkdir -p "${SHVR_DIR_SRC}/brush"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://github.com/reubeno/brush/archive/refs/tags/brush-shell-v${version}.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_brush ()
{
	shvr_versioninfo_brush "$1"

	mkdir -p "${build_srcdir}"

	shvr_deps_brush "$1"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	cargo build --release

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
		sh "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh" -y
	fi

	. "$HOME/.cargo/env"
}
