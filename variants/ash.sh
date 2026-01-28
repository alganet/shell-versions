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
	# Extract with fixed ownership, mode, and time for reproducibility
	tar --extract \
		--file="${build_srcdir}.tar.bz2" \
		--strip-components=1 \
		--directory="${build_srcdir}" \
		--owner=0 \
		--group=0 \
		--mode=go-w \
		--touch

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
	make allnoconfig

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
	make oldconfig

	# Fix .config timestamp for reproducibility
	# Replace the auto-generated timestamp line with a fixed value
	sed -i -e "s/^# .* [0-9][0-9]:[0-9][0-9]:[0-9][0-9] [0-9]\{4\}$/# Thu Jan  1 00:00:01 UTC 1970/" .config
	# Verify that the timestamp normalization succeeded; warn if the format changed
	if ! grep -q '^# Thu Jan  1 00:00:01 UTC 1970$' .config
	then
		echo "Warning: failed to normalize .config timestamp; format may have changed" >&2
	fi

	# Fix autoconf.h timestamp for reproducibility (regenerated during make)
	# This must be done before the build to affect the compiled binary
	sed -i -e 's/#define AUTOCONF_TIMESTAMP.*/#define AUTOCONF_TIMESTAMP "1970-01-01 00:00:01 UTC"/' include/autoconf.h 2>/dev/null || true

	# Verify unset configs are disabled
	for conf in $unsetConfs
	do ! grep -q "^$conf=" .config
	done

	# Build busybox with reproducible flags
	# Use fixed source date epoch and disable compiler timestamp features
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CFLAGS="-Os -frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"
	export RANLIB="ranlib -D"
	export AR="ar -D"

	# Single-threaded build for deterministic ordering
	make \
		KBUILD_BUILD_TIMESTAMP="Thu Jan  1 00:00:01 UTC 1970" \
		KBUILD_BUILD_USER="builder" \
		KBUILD_BUILD_HOST="builder"

	unset SOURCE_DATE_EPOCH TZ CFLAGS LDFLAGS RANLIB AR

	# Install binary
	mkdir -p "${SHVR_DIR_OUT}/ash_${version}/bin"
	cp "busybox" "${SHVR_DIR_OUT}/ash_${version}/bin/ash"

	# Strip binary to ensure reproducible output
	strip --strip-all "${SHVR_DIR_OUT}/ash_${version}/bin/ash"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/ash_${version}/bin/ash"
	chmod 755 "${SHVR_DIR_OUT}/ash_${version}/bin/ash"

	# Test the built shell
	"${SHVR_DIR_OUT}/ash_${version}/bin/ash" -c "echo busybox ash version $version"
}

shvr_deps_ash ()
{
	shvr_versioninfo_ash "$1"
	apt-get -y install \
		curl bzip2 gcc make binutils
}