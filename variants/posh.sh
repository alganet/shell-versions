#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_posh ()
{
	cat <<-@
		posh_0.14.2
		posh_0.13.2
	@
}

shvr_targets_posh ()
{
	cat <<-@
		posh_0.14.2
		posh_0.13.2
		posh_0.12.6
	@
}

shvr_versioninfo_posh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/posh/${version}"
}

shvr_download_posh ()
{
	shvr_versioninfo_posh "$1"

	mkdir -p "${SHVR_DIR_SRC}/posh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://salsa.debian.org/clint/posh/-/archive/debian/$version/posh-debian-$version.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_posh ()
{
	shvr_versioninfo_posh "$1"

	mkdir -p "${build_srcdir}"

	shvr_deps_posh "$1"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	autoreconf -fi
	./configure \
		--prefix="${SHVR_DIR_OUT}/posh_$version"

	make -j "$(nproc)"
	mkdir -p "${SHVR_DIR_OUT}/posh_${version}/bin"
	cp "posh" "${SHVR_DIR_OUT}/posh_$version/bin"

	"${SHVR_DIR_OUT}/posh_${version}/bin/posh" -c "echo posh version $version"
}

shvr_deps_posh ()
{
	shvr_versioninfo_posh "$1"
	apt-get -y install \
		wget gcc make autoconf automake
}
