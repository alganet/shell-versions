#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_busybox ()
{
	shvr_cache targets_busybox \
		curl --no-progress-meter "https://busybox.net/downloads/" |
			grep -Eoi 'href="[^"]*"' |
			sed -n '
				s/^href="busybox-/busybox_/
				s/"$//
				/^busybox_[0-9][0-9]*.*\.tar\.bz2$/ {
					s/\.tar\.bz2$//
					p
				}
			' |
			grep "^busybox_1\.[0-9][0-9]" |
			grep -v "^busybox_1\.[0-1][0-9]" |
			grep -v "^busybox_1\.20\." |
			sort -u |
			sort -V -r
}

shvr_majors_busybox () { shvr_semver_majors busybox; }
shvr_minors_busybox () { shvr_semver_minors busybox "$@"; }
shvr_patches_busybox () { shvr_semver_patches busybox "$@"; }

shvr_build_busybox ()
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
	
	build_srcdir="${SHVR_DIR_SRC}/busybox/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget bzip2 gcc make
	wget -O "${build_srcdir}.tar.bz2" \
		"https://busybox.net/downloads/busybox-${version}.tar.bz2"

	mkdir -p /usr/src/busybox
	tar --extract \
		--file="${build_srcdir}.tar.bz2" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	setConfs='
		CONFIG_LAST_SUPPORTED_WCHAR=0
		CONFIG_ASH_ALIAS=y
		CONFIG_ASH_CMDCMD=y
		CONFIG_ASH_ECHO=y
		CONFIG_ASH_INTERNAL_GLOB=y
		CONFIG_ASH_JOB_CONTROL=y
		CONFIG_ASH_PRINTF=y
		CONFIG_ASH_RANDOM_SUPPORT=y
		CONFIG_ASH_TEST=y
		CONFIG_ASH=y
		CONFIG_ECHO=y
		CONFIG_FEATURE_SH_MATH_64=y
		CONFIG_FEATURE_SH_MATH=y
		CONFIG_HUSH_CASE=y
		CONFIG_HUSH_COMMAND=y
		CONFIG_HUSH_ECHO=y
		CONFIG_HUSH_EXPORT_N=y
		CONFIG_HUSH_EXPORT=y
		CONFIG_HUSH_FUNCTIONS=y
		CONFIG_HUSH_IF=y
		CONFIG_HUSH_INTERACTIVE=y
		CONFIG_HUSH_JOB=y
		CONFIG_HUSH_KILL=y
		CONFIG_HUSH_LOCAL=y
		CONFIG_HUSH_LOOPS=y
		CONFIG_HUSH_MODE_X=y
		CONFIG_HUSH_PRINTF=y
		CONFIG_HUSH_RANDOM_SUPPORT=y
		CONFIG_HUSH_READ=y
		CONFIG_HUSH_SET=y
		CONFIG_HUSH_TEST=y
		CONFIG_HUSH_TICK=y
		CONFIG_HUSH_TRAP=y
		CONFIG_HUSH_TYPE=y
		CONFIG_HUSH_ULIMIT=y
		CONFIG_HUSH_UMASK=y
		CONFIG_HUSH_UNSET=y
		CONFIG_HUSH_WAIT=y
		CONFIG_HUSH=y
		CONFIG_TEST=y
	'

	unsetConfs='
		CONFIG_ASH_OPTIMIZE_FOR_SIZE
	'
	
	make allnoconfig
	
	for conf in $unsetConfs
	do
		sed -i \
			-e "s!^$conf=.*\$!# $conf is not set!" \
			.config
	done
	
	for confV in $setConfs
	do
		conf="${confV%=*}"
		sed -i \
			-e "s!^$conf=.*\$!$confV!" \
			-e "s!^# $conf is not set\$!$confV!" \
			.config
		if ! grep -q "^$confV\$" .config
		then echo "$confV" >> .config
		fi
	done
	
	make oldconfig
	
	for conf in $unsetConfs
	do ! grep -q "^$conf=" .config
	done

	for confV in $setConfs
	do
		if ! grep -q "^$confV\$" .config
		then
			if test "${version_major}" = 1 -a "${version_minor}" -lt 26
			then
				case "$confV" in
					'CONFIG_ASH_ECHO=y') ;;
					'CONFIG_ASH_INTERNAL_GLOB=y') ;;
					'CONFIG_ASH_PRINTF=y') ;;
					'CONFIG_ASH_TEST=y') ;;
					'CONFIG_FEATURE_SH_MATH_64=y') ;;
					'CONFIG_FEATURE_SH_MATH=y') ;;
					'CONFIG_HUSH_COMMAND=y') ;;
					'CONFIG_HUSH_ECHO=y') ;;
					'CONFIG_HUSH_EXPORT=y') ;;
					'CONFIG_HUSH_KILL=y') ;;
					'CONFIG_HUSH_PRINTF=y') ;;
					'CONFIG_HUSH_READ=y') ;;
					'CONFIG_HUSH_SET=y') ;;
					'CONFIG_HUSH_TEST=y') ;;
					'CONFIG_HUSH_TRAP=y') ;;
					'CONFIG_HUSH_TYPE=y') ;;
					'CONFIG_HUSH_ULIMIT=y') ;;
					'CONFIG_HUSH_UMASK=y') ;;
					'CONFIG_HUSH_UNSET=y') ;;
					'CONFIG_HUSH_WAIT=y') ;;
					*)
						echo "Fail $confV"
						exit 1
						;;
				esac
			elif test "${version_major}" = 1 -a "${version_minor}" -lt 27
			then
				case "$confV" in
					'CONFIG_ASH_ECHO=y') ;;
					'CONFIG_ASH_PRINTF=y') ;;
					'CONFIG_ASH_TEST=y') ;;
					'CONFIG_HUSH_COMMAND=y') ;;
					'CONFIG_HUSH_ECHO=y') ;;
					'CONFIG_HUSH_EXPORT=y') ;;
					'CONFIG_HUSH_KILL=y') ;;
					'CONFIG_HUSH_PRINTF=y') ;;
					'CONFIG_HUSH_READ=y') ;;
					'CONFIG_HUSH_SET=y') ;;
					'CONFIG_HUSH_TEST=y') ;;
					'CONFIG_HUSH_TRAP=y') ;;
					'CONFIG_HUSH_TYPE=y') ;;
					'CONFIG_HUSH_ULIMIT=y') ;;
					'CONFIG_HUSH_UMASK=y') ;;
					'CONFIG_HUSH_UNSET=y') ;;
					'CONFIG_HUSH_WAIT=y') ;;
					*)
						echo "Fail $confV"
						exit 1
						;;
				esac
			elif test "${version_major}" = 1 -a "${version_minor}" -lt 29
			then
				case "$confV" in
					'CONFIG_HUSH_COMMAND=y') ;;
					*)
						echo "Fail $confV"
						exit 1
						;;
				esac
			else
				echo "Fail $confV"
				exit 1
			fi
		fi
	done

	make -j "$(nproc)"

	mkdir -p "${SHVR_DIR_OUT}/busybox_${version}/bin"
	cp "busybox" "${SHVR_DIR_OUT}/busybox_$version/bin"
	
	"${SHVR_DIR_OUT}/busybox_${version}/bin/busybox" ash -c "echo busybox ash version $version"
	"${SHVR_DIR_OUT}/busybox_${version}/bin/busybox" hush -c "echo busybox hush version $version"
}
