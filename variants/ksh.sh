#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_ksh ()
{
	shvr_cache targets_ksh_93 \
		curl --no-progress-meter https://api.github.com/repos/ksh93/ksh/tags |
			sed -n '
				/^    "name": "/ {
					s/^    "name": "/ksh_shvrA93uplusm-/
					s/",$//
					p
				}
			' |
			sed '/reboot\|rc\|beta/d' 
			

	shvr_cache targets_ksh_2020 \
		curl --no-progress-meter https://api.github.com/repos/ksh2020/ksh/tags |
			sed -n '
				/^    "name": "/ {
					s/^    "name": "/ksh_shvrB2020-/
					s/",$//
					p
				}
			' |
			sed '/alpha\|beta\|rc\|93\|2017/d' | sort -n -r
		
	shvr_cache targets_ksh_history3 \
		curl --no-progress-meter "https://api.github.com/repos/ksh93/ksh93-history/branches?per_page=100&page=3" |
			sed -n '
				/^    "name": "/ {
					s/^    "name": "/ksh_shvrChistory-/
					s/",$//
					p
				}
			' | sort -n -r | grep -v 'master'
	shvr_cache targets_ksh_history2 \
		curl --no-progress-meter "https://api.github.com/repos/ksh93/ksh93-history/branches?per_page=100&page=2" |
			sed -n '
				/^    "name": "/ {
					s/^    "name": "/ksh_shvrChistory-/
					s/",$//
					p
				}
			' | sort -n -r | grep -v 'master'
	shvr_cache targets_ksh_history1 \
		curl --no-progress-meter "https://api.github.com/repos/ksh93/ksh93-history/branches?per_page=100&page=1" |
			sed -n '
				/^    "name": "/ {
					s/^    "name": "/ksh_shvrChistory-/
					s/",$//
					p
				}
			' | sort -n -r | grep -v 'master'
}

shvr_majors_ksh ()
{
	shvr_targets_ksh | sed -n 's/^ksh_\([^-]*\-[^.0-9]*[0-9]*\).*$/ksh_\1/p' | grep -v 'b_2013' | grep -v 'b_200[0-3]' | grep -v 'b_199' | uniq
}

shvr_minors_ksh ()
{
	shvr_targets_ksh | sed -n 's/^\('$1'\)\(.*\)$/\1/p' | uniq | sort -V -r
}

shvr_patches_ksh ()
{
	shvr_targets_ksh | sed -n 's/^\('$1'\)\(.*\)$/\1\2/p' | sort -u | sort -r
}


shvr_build_ksh ()
{
	version="$1"
	fork_name="${1%%-*}"
	fork_version="${version#"${fork_name}-"}"
	build_srcdir="${SHVR_DIR_SRC}/ksh/${version}"
	mkdir -p "${build_srcdir}"
	
	case "$fork_name" in
		'shvrA93uplusm')
			apt-get -y install \
				wget gcc
			wget -O "${build_srcdir}.tar.gz" \
				"https://github.com/ksh93/ksh/archive/refs/tags/${fork_version}.tar.gz"
			;;
		'shvrB2020')
			apt-get -y install \
				wget gcc meson
			wget -O "${build_srcdir}.tar.gz" \
				"https://github.com/ksh2020/ksh/archive/refs/tags/${fork_version}.tar.gz"
			;;
		'shvrChistory')
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
