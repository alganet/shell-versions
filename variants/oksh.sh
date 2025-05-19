#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_oksh ()
{
	cat <<-@
		oksh_7.7
		oksh_7.6
	@
}

shvr_targets_oksh ()
{
	cat <<-@
		oksh_7.7
		oksh_7.6
		oksh_7.5
		oksh_7.4
		oksh_7.3
		oksh_7.2
		oksh_7.1
		oksh_7.0
		oksh_6.9
		oksh_6.8.1
		oksh_6.7.1
		oksh_6.6
		oksh_6.5
	@
}

shvr_build_oksh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/oksh/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc make
	wget -O "${build_srcdir}.tar.xz" \
		"https://github.com/ibara/oksh/releases/download/oksh-$version/oksh-$version.tar.gz"

	tar --extract \
		--file="${build_srcdir}.tar.xz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	./configure \
		--disable-curses \
		--prefix="${SHVR_DIR_OUT}/oksh_$version"

	make -j "$(nproc)"
	mkdir -p "${SHVR_DIR_OUT}/oksh_${version}/bin"
	cp "oksh" "${SHVR_DIR_OUT}/oksh_$version/bin"
	
	"${SHVR_DIR_OUT}/oksh_${version}/bin/oksh" -c "echo oksh version $version"
}
