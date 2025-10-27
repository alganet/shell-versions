#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
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

shvr_build_brush ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/brush/${version}"
	mkdir -p "${build_srcdir}"
	
	apt-get -y install \
		curl wget gcc
    
	if ! test -f "$HOME/.cargo/env"
	then
		curl -o "$HOME/rustup.sh" --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs
		cd $HOME
		sh rustup.sh -y
	fi

	. "$HOME/.cargo/env"

	wget -O "${build_srcdir}.tar.gz" \
		"https://github.com/reubeno/brush/archive/refs/tags/brush-shell-v${version}.tar.gz"

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
