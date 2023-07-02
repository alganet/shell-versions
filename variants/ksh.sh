#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_ksh ()
{
	cat <<-@
		ksh_93u+m-v1.0.4
		ksh_93u+m-v1.0.3
		ksh_93u+m-v1.0.2
		ksh_93u+m-v1.0.1
		ksh_2020-2020.0.0
		ksh_history-b_2016-01-10
		ksh_history-b_2012-08-01
		ksh_history-b_2011-03-10
		ksh_history-b_2010-10-26
		ksh_history-b_2010-06-21
		ksh_history-b_2008-11-04
		ksh_history-b_2008-06-08
		ksh_history-b_2008-02-02
		ksh_history-b_2007-01-11
		ksh_history-b_2006-11-15
		ksh_history-b_2006-07-24
		ksh_history-b_2006-02-14
		ksh_history-b_2005-09-16
		ksh_history-b_2005-06-01
		ksh_history-b_2005-02-02
		ksh_history-b_2004-10-11
	@
}

shvr_build_ksh ()
{
	version="$1"
	fork_name="${1%%-*}"
	fork_version="${1#*-}"
	build_srcdir="${SHVR_DIR_SRC}/ksh/${version}"
	mkdir -p "${build_srcdir}"
	
	case "$fork_name" in
		'93u+m')
			apt-get -y install \
				wget gcc
			wget -O "${build_srcdir}.tar.gz" \
				"https://github.com/ksh93/ksh/archive/refs/tags/${fork_version}.tar.gz"
			;;
		'2020')
			apt-get -y install \
				wget gcc meson
			wget -O "${build_srcdir}.tar.gz" \
				"https://github.com/ksh2020/ksh/archive/refs/tags/${fork_version}.tar.gz"
			;;
		'history')
			apt-get -y install \
				wget gcc
			wget -O "${build_srcdir}.tar.gz" \
				"https://api.github.com/repos/ksh93/ksh93-history/tarball/${fork_version}"
			;;
	esac

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	if test -f "bin/package"
	then
		bin/package make

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		host_type="$(bin/package host type)"
		cp "arch/${host_type}/bin/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
		cp "arch/${host_type}/bin/shcomp" "${SHVR_DIR_OUT}/ksh_${version}/bin/shcomp"
	elif test -f "meson.build"
	then
		meson \
			--prefix="${SHVR_DIR_OUT}/ksh_$version" \
			build

		ninja -C build

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		cp "build/src/cmd/ksh93/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
		cp "build/src/cmd/ksh93/shcomp" "${SHVR_DIR_OUT}/ksh_${version}/bin/shcomp"
	fi
	
	"${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" -c "echo ksh version $version"
}
