#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/busybox.sh"

shvr_current_hush ()
{
	shvr_current_busybox "$@" | sed -e 's/^busybox_/hush_/'
}

shvr_targets_hush ()
{
	shvr_targets_busybox "$@" | sed -e 's/^busybox_/hush_/'
}

shvr_versioninfo_hush ()
{
	shvr_versioninfo_busybox "$@"
}

shvr_download_hush ()
{
	shvr_download_busybox "$@"
}

shvr_build_hush ()
{
	shvr_versioninfo_hush "$1"

	mkdir -p "${build_srcdir}"

	# Install build dependencies
	apt-get -y install \
		wget bzip2 gcc make

	mkdir -p /usr/src/busybox
	tar --extract \
		--file="${build_srcdir}.tar.bz2" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	# Configurations to enable for hush-focused builds.
	# Includes hush features, static linking, and individual applet support.
	setConfs='
		CONFIG_FEATURE_SH_IS_HUSH=y
		CONFIG_LAST_SUPPORTED_WCHAR=0
		CONFIG_ECHO=y
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

	# Start with minimal config (all disabled)
	make -j "$(nproc)" allnoconfig

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
	mkdir -p "${SHVR_DIR_OUT}/hush_${version}/bin"
	cp "busybox" "${SHVR_DIR_OUT}/hush_${version}/bin/hush"

	# Test the built shell
	"${SHVR_DIR_OUT}/hush_${version}/bin/hush" -c "echo busybox hush version $version"
}