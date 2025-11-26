#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_osh ()
{
	cat <<-@
		osh_0.36.0
		osh_0.35.0
	@
}

shvr_targets_osh ()
{
	cat <<-@
		osh_0.36.0
		osh_0.35.0
		osh_0.34.0
		osh_0.33.0
		osh_0.32.0
		osh_0.31.0
		osh_0.30.0
		osh_0.29.0
		osh_0.28.0
		osh_0.27.0
		osh_0.26.0
		osh_0.25.0
	@
}

shvr_versioninfo_osh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/osh/${version}"
}

shvr_download_osh ()
{
	shvr_versioninfo_osh "$1"

	mkdir -p "${SHVR_DIR_SRC}/osh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://oils.pub/download/oils-for-unix-${version}.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_osh ()
{
	shvr_versioninfo_osh "$1"

	mkdir -p "${build_srcdir}"

	shvr_deps_osh "$1"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	./configure \
		--without-readline \
		--prefix="${SHVR_DIR_OUT}/osh_$version"

	_build/oils.sh
	mkdir -p "${SHVR_DIR_OUT}/osh_${version}/bin"
	cp "_bin/cxx-opt-sh/oils-for-unix" "${SHVR_DIR_OUT}/osh_$version/bin/osh"

	"${SHVR_DIR_OUT}/osh_${version}/bin/osh" -c "echo osh version $version"
}

shvr_deps_osh ()
{
	shvr_versioninfo_osh "$1"
	apt-get -y install \
		wget gcc g++ make
}
