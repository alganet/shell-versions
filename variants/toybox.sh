#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_toybox ()
{
	cat <<-@
	@
}

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
