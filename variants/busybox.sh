#!/usr/bin/env sh

# ISC License
#
# Copyright (c) 2023 Alexandre Gomes Gaigalas <alganet@gmail.com>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

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
