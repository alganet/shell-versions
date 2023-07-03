#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_bash ()
{
	shvr_cache targets_bash \
		curl --no-progress-meter "https://ftp.gnu.org/gnu/bash/" |
			grep -Eo 'href="[^"]*"' |
			sed -n '
				s/^href="bash-/bash_/
				s/"$//
				/^bash_[0-9][0-9]*.*\.tar\.gz$/ {
					s/\.tar\.gz$//
					p
				}
				/^bash_[0-9][0-9]*.*-patches\/$/ {
					s/^bash_/bash-/
					p
				}
			' |
			while read -r possible_version
			do
				if test "${possible_version%"patches/"}" != "$possible_version"
				then
					shvr_cache "targets_bash${possible_version%'/'}" \
						curl --no-progress-meter "https://ftp.gnu.org/gnu/bash/$possible_version" |
							grep -Eo 'href="[^"]*"' |
							sed -n '
								s/^href="//
								s/"$//
								/^bash.*[0-9][0-9][0-9]$/ {
									p
								}
							' |
							sort -V |
							cut -d'-' -f2 |
							sed "s/^/${possible_version%'/'}/" |
							sed 's/^bash-/bash_/; s/-patches[0]*/./'
				else echo "$possible_version"
				fi
			done |
			grep -v "^bash_[0-2]\." |
			sort -u |
			sort -V -r
}

shvr_majors_bash () { shvr_semver_majors bash; }
shvr_minors_bash () { shvr_semver_minors bash "$@"; }
shvr_patches_bash () { shvr_semver_patches bash "$@"; }

shvr_build_bash ()
{
	version="$1"
	version_major="${version%%\.*}"
	
	if test "$version" = "$version_major"
	then return 1
	fi
	
	version_minor="${version#$version_major\.}"
	version_patch="${version_minor#*\.}"
	
	if test "$version_patch" = "$version_minor"
	then return 1
	else version_minor="${version_minor%\.*}"
	fi
	
	version_baseline="${version_major}.${version_minor}"
	build_srcdir="${SHVR_DIR_SRC}/bash/${version_baseline}"
	mkdir -p "${build_srcdir}"

	if test "$version_baseline" = "4.0"
	then apt-get -y install \
			wget patch gcc bison make autoconf
	elif test "$version_baseline" = "3.0"
	then apt-get -y install \
			wget patch gcc bison make ncurses-dev
	else apt-get -y install \
			wget patch gcc bison make
	fi
	
	wget -O "${build_srcdir}.tar.gz" \
		"https://ftp.gnu.org/gnu/bash/bash-${version_baseline}.tar.gz"
	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	mkdir -p "${build_srcdir}-patches"
	patch_i=0
	while test $patch_i -lt $version_patch
	do
		patch_i=$((patch_i + 1))
		patch_n="$(printf '%03d' "$patch_i")"
		url="https://ftp.gnu.org/gnu/bash/bash-${version_baseline}-patches/bash${version_major}${version_minor}-${patch_n}"
		wget -O "${build_srcdir}-patches/$patch_n" "$url"
		patch \
			--directory="${build_srcdir}" \
			--input="${build_srcdir}-patches/$patch_n" \
			--strip=0
	done
	
	cd "${build_srcdir}"

	./configure \
		--prefix="${SHVR_DIR_OUT}/bash_${version}"

	make -j "$(nproc)"

	mkdir -p "${SHVR_DIR_OUT}/bash_${version}/bin"
	cp bash "${SHVR_DIR_OUT}/bash_${version}/bin/bash"

	"${SHVR_DIR_OUT}/bash_${version}/bin/bash" --version
}
