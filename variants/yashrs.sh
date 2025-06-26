#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_yashrs ()
{
	cat <<-@
		yashrs_0.4.2
		yashrs_0.4.1
	@
}

shvr_targets_yashrs ()
{
	cat <<-@
		yashrs_0.4.2
		yashrs_0.4.1
		yashrs_0.4.0
		yashrs_0.3.0
	@
}

shvr_build_yashrs ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/yashrs/${version}"
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
		"https://github.com/magicant/yash-rs/archive/refs/tags/yash-cli-${version}.tar.gz"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	cargo build --release

	mkdir -p "${SHVR_DIR_OUT}/yashrs_${version}/bin"
	cp "./target/release/yash3" "${SHVR_DIR_OUT}/yashrs_$version/bin"
	
	"${SHVR_DIR_OUT}/yashrs_${version}/bin/yash3" -c "echo yashrs version $version"
}
