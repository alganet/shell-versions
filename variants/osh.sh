#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_osh ()
{
	cat <<-@
		osh_0.33.0
		osh_0.32.0
	@
}

shvr_targets_osh ()
{
	cat <<-@
		osh_0.33.0
		osh_0.32.0
		osh_0.31.0
		osh_0.30.0
		osh_0.29.0
		osh_0.28.0
		osh_0.27.0
		osh_0.26.0
		osh_0.25.0
		osh_0.24.0
		osh_0.23.0
		osh_0.22.0
	@
}

shvr_build_osh ()
{
	version="$1"
	version_major="${version%%\.*}"

	if test "$version" = "$version_major"
	then return 1
	fi

	version_minor="${version#$version_major\.}"
	version_patch="${version_minor#*[.-]}"

	if test "$version_patch" = "$version_minor"
	then return 1
	else version_minor="${version_minor%\.*}"
	fi

	build_srcdir="${SHVR_DIR_SRC}/osh/${version}"
	mkdir -p "${build_srcdir}"

	if test "$version_major" = 0 && test "$version_minor" -lt 25
	then
		apt-get -y install \
			wget gcc make
		wget -O "${build_srcdir}.tar.gz" \
			"https://www.oilshell.org/download/oil-${version}.tar.gz"
	else
		apt-get -y install \
			wget gcc g++ make
		wget -O "${build_srcdir}.tar.gz" \
			"https://oils.pub/download/oils-for-unix-${version}.tar.gz"
	fi

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	./configure \
		--without-readline \
		--prefix="${SHVR_DIR_OUT}/osh_$version"

	if test "$version_major" = 0 && test "$version_minor" -lt 25
	then
		make -j "$(nproc)"
		mkdir -p "${SHVR_DIR_OUT}/osh_${version}/bin"
		cp "_bin/oil.ovm" "${SHVR_DIR_OUT}/osh_$version/bin/osh"
	else
		_build/oils.sh
		mkdir -p "${SHVR_DIR_OUT}/osh_${version}/bin"
		cp "_bin/cxx-opt-sh/oils-for-unix" "${SHVR_DIR_OUT}/osh_$version/bin/osh"
	fi


	"${SHVR_DIR_OUT}/osh_${version}/bin/osh" -c "echo osh version $version"
}
