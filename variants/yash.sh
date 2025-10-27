#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_yash ()
{
	cat <<-@
		yash_2.60
		yash_2.59
	@
}

shvr_targets_yash ()
{
	cat <<-@
		yash_2.60
		yash_2.59
		yash_2.58.1
		yash_2.57
		yash_2.56.1
		yash_2.55
		yash_2.54
		yash_2.53
		yash_2.52
		yash_2.51
		yash_2.50
		yash_2.49
		yash_2.48
		yash_2.47
		yash_2.46
		yash_2.45
		yash_2.44
		yash_2.43
		yash_2.42
		yash_2.41
	@
}

shvr_build_yash ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/yash/${version}"
	mkdir -p "${build_srcdir}"
	
	apt-get -y install \
		wget gcc make xz-utils
	wget -O "${build_srcdir}.tar.gz" \
		"https://github.com/magicant/yash/releases/download/${version}/yash-${version}.tar.xz"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	./configure \
		--disable-nls \
		--disable-lineedit \
		--prefix="${SHVR_DIR_OUT}/yash_$version"

	make -j "$(nproc)"

	mkdir -p "${SHVR_DIR_OUT}/yash_${version}/bin"
	cp "yash" "${SHVR_DIR_OUT}/yash_$version/bin"
	
	"${SHVR_DIR_OUT}/yash_${version}/bin/yash" -c "echo yash version $version"
}
