#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/busybox.sh"

shvr_current_ash ()
{
	shvr_current_busybox "$@" | sed -e 's/^busybox_/ash_/'
}

shvr_targets_ash ()
{
	shvr_targets_busybox "$@" | sed -e 's/^busybox_/ash_/'
}

shvr_versioninfo_ash ()
{
	shvr_versioninfo_busybox "$@"
}

shvr_download_ash ()
{
	shvr_download_busybox "$@"
}

shvr_build_ash ()
{
	shvr_versioninfo_ash "$1"

	mkdir -p "${build_srcdir}"
	mkdir -p /usr/src/busybox
	tar --extract \
		--file="${build_srcdir}.tar.bz2" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	# Configurations to enable for ash-focused builds.
	# Includes ash features, static linking, and individual applet support.
	setConfs='
		CONFIG_FEATURE_SH_IS_ASH=y
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
		CONFIG_TEST=y
	'

	# Configurations to explicitly disable.
	unsetConfs='
		CONFIG_ASH_OPTIMIZE_FOR_SIZE
	'

	# Start with minimal config (all disabled)
	make -j "$(nproc)" allnoconfig

	# Disable specified configs
	for conf in $unsetConfs
	do
		sed -i \
			-e "s!^$conf=.*\$!# $conf is not set!" \
			.config
	done

	# Enable specified configs
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

	# Resolve config dependencies
	make -j "$(nproc)" oldconfig

	# Verify unset configs are disabled
	for conf in $unsetConfs
	do ! grep -q "^$conf=" .config
	done

	# Build busybox
	make -j "$(nproc)"

	# Install binary
	mkdir -p "${SHVR_DIR_OUT}/ash_${version}/bin"
	cp "busybox" "${SHVR_DIR_OUT}/ash_${version}/bin/ash"

	# Test the built shell
	"${SHVR_DIR_OUT}/ash_${version}/bin/ash" -c "echo busybox ash version $version"
}

shvr_deps_ash ()
{
	shvr_versioninfo_ash "$1"
	apt-get -y install \
		wget bzip2 gcc make
}