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

shvr_build_toybox ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/toybox/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc make
	wget -O "${build_srcdir}.tar.gz" \
		"https://api.github.com/repos/landley/toybox/tarball/${version}"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"


	setConfs='
		CONFIG_TOYBOX=y
		CONFIG_TOYBOX_FLOAT=y
		CONFIG_SH=y
		CONFIG_TEST=y
		CONFIG_ECHO=y
		CONFIG_TIME=y
	'

	unsetConfs='
	'
	
	make defconfig
	
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
			echo "Fail $confV"
			exit 1
		fi
	done

	make -j "$(nproc)"
	mkdir -p "${SHVR_DIR_OUT}/toybox_${version}/bin"
	cp "./toybox" "${SHVR_DIR_OUT}/toybox_$version/bin"
	
	"${SHVR_DIR_OUT}/toybox_${version}/bin/toybox" sh -c "echo toybox version $version"
}
