#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_yashrs ()
{
	cat <<-@
		yashrs_3.0.3
		yashrs_0.4.5
	@
}

shvr_targets_yashrs ()
{
	cat <<-@
		yashrs_3.0.3
		yashrs_3.0.2
		yashrs_3.0.1
		yashrs_3.0.0
		yashrs_0.4.5
		yashrs_0.4.4
		yashrs_0.4.3
		yashrs_0.4.2
		yashrs_0.4.1
		yashrs_0.4.0
		yashrs_0.3.0
	@
}

shvr_versioninfo_yashrs ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/yashrs/${version}"
}

shvr_download_yashrs ()
{
	shvr_versioninfo_yashrs "$1"

	mkdir -p "${SHVR_DIR_SRC}/yashrs"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		wget -O "${build_srcdir}.tar.gz" \
			"https://github.com/magicant/yash-rs/archive/refs/tags/yash-cli-${version}.tar.gz"
	fi
}

shvr_build_yashrs ()
{
	shvr_versioninfo_yashrs "$1"

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
