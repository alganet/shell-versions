#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_ksh ()
{
	cat <<-@
		ksh_shvrA93uplusm-v1.0.10
		ksh_shvrA93uplusm-v1.0.9
	@
}

shvr_targets_ksh ()
{
	cat <<-@
		ksh_shvrA93uplusm-v1.0.10
		ksh_shvrA93uplusm-v1.0.9
		ksh_shvrA93uplusm-v1.0.8
		ksh_shvrA93uplusm-v1.0.7
		ksh_shvrA93uplusm-v1.0.6
		ksh_shvrA93uplusm-v1.0.4
		ksh_shvrA93uplusm-v1.0.3
		ksh_shvrA93uplusm-v1.0.2
		ksh_shvrA93uplusm-v1.0.1
		ksh_shvrB2020-2020.0.0
		ksh_shvrChistory-b_2016-01-10
		ksh_shvrChistory-b_2012-08-01
		ksh_shvrChistory-b_2011-03-10
		ksh_shvrChistory-b_2010-10-26
		ksh_shvrChistory-b_2010-06-21
		ksh_shvrChistory-b_2008-11-04
		ksh_shvrChistory-b_2008-06-08
		ksh_shvrChistory-b_2008-02-02
		ksh_shvrChistory-b_2007-01-11
	@
}

shvr_versioninfo_ksh ()
{
	version="$1"
	fork_name="${1%%-*}"
	fork_version="${1#*-}"
	build_srcdir="${SHVR_DIR_SRC}/ksh/${version}"
}

shvr_download_ksh ()
{
	shvr_versioninfo_ksh "$1"

	mkdir -p "${SHVR_DIR_SRC}/ksh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		case "$fork_name" in
			*'93uplusm')
				wget -O "${build_srcdir}.tar.gz" \
					"https://github.com/ksh93/ksh/archive/refs/tags/${fork_version}.tar.gz"
				;;
			*'2020')
				wget -O "${build_srcdir}.tar.gz" \
					"https://github.com/ksh2020/ksh/archive/refs/tags/${fork_version}.tar.gz"
				;;
			*'history')
				wget -O "${build_srcdir}.tar.gz" \
					"https://api.github.com/repos/ksh93/ksh93-history/tarball/${fork_version}"
				;;
		esac
	fi
}

shvr_build_ksh ()
{
	shvr_versioninfo_ksh "$1"

	mkdir -p "${build_srcdir}"

	case "$fork_name" in
		*'93uplusm')
			apt-get -y install \
				wget gcc
			;;
		*'2020')
			apt-get -y install \
				wget gcc meson
			;;
		*'history')
			apt-get -y install \
				wget gcc patch
			;;
	esac

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	if test -d "${SHVR_DIR_SELF}/patches/ksh/$version"
	then
		find "${SHVR_DIR_SELF}/patches/ksh/$version" -type f | sort | while read -r patch_file
		do patch -p0 < "$patch_file"
		done
	fi

	if test -f "bin/package"
	then
		bin/package make

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		host_type="$(bin/package host type)"
		cp "arch/${host_type}/bin/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	elif test -f "meson.build"
	then
		meson \
			--prefix="${SHVR_DIR_OUT}/ksh_$version" \
			build

		ninja -C build

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		cp "build/src/cmd/ksh93/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	fi

	"${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" -c "echo ksh version $version"
}
