#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/busybox.sh"
. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/patches.sh"

shvr_static_ash ()
{
	return 0
}

shvr_current_ash ()
{
	shvr_current_busybox "$@" | sed -e 's/^busybox_/ash_/'
}

shvr_targets_ash ()
{
	shvr_targets_busybox "$@" | sed -e 's/^busybox_/ash_/'
}

shvr_prerelease_ash ()
{
	shvr_prerelease_busybox "$@" | sed -e 's/^busybox_/ash_/'
}

shvr_snapshot_ash ()
{
	shvr_snapshot_busybox "$@" | sed -e 's/^busybox_/ash_/'
}

shvr_update_ash ()
{
	shvr_update_busybox
}

# ash carries no versions/ash.all; its versions (and their dates) are busybox's.
shvr_versionsource_ash ()
{
	echo busybox
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

	# ash and hush share build_srcdir (busybox/<version>). Remove any prior
	# extraction/build tree so a fresh source is unpacked every time; otherwise
	# building both shells of one version in a single container (e.g.
	# `shvr.sh build ash_X hush_X`, as the Dockerfile does) leaves stale objects
	# that contaminate the second build and break reproducibility on old busybox.
	rm -rf "${build_srcdir}"
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

	# The busybox patch set: ash and hush build from the same tree and share it.
	shvr_apply_patches ash "$version"

	# Configurations to enable for ash-focused builds.
	# Includes ash features, static linking, and individual applet support.
	#
	# Renamed-symbol handling: BusyBox renamed several symbols over time
	# (e.g. ASH_BUILTIN_ECHO -> ASH_ECHO at 1.27.2, FEATURE_SH_IS_ASH ->
	# SH_IS_ASH). allnoconfig + sed + oldconfig silently drops symbols absent
	# from a given version, so we list EVERY historical name; whichever exists
	# is applied. Without the legacy names, old ash (<=1.26.2 and the 1.2.x
	# island) ships with no echo/printf/test builtin and no arithmetic.
	#
	# Arithmetic went through THREE names, so all three are listed:
	#   ASH_MATH_SUPPORT(_64)      1.2.2 .. 1.13.4
	#   SH_MATH_SUPPORT(_64)       1.16.2 .. 1.25.1
	#   FEATURE_SH_MATH(_64)       1.26.2 ..   (plus _BASE from 1.37.0)
	# The oldest name was missing here, which silently left $(( )) disabled
	# across the whole 1.2.2..1.13.4 band -- those builds answered arithmetic
	# examples with "We unsupport $((arith))" / "you disabled math support",
	# which reads as a shell limitation but was ours. 1.2.2's kconfig declares
	# the symbol as `config CONFIG_ASH_MATH_SUPPORT` and writes "%s=y" with no
	# added prefix, so the .config key is CONFIG_ASH_MATH_SUPPORT there too --
	# one line covers both kconfig eras.
	#
	# hush is deliberately NOT given a math alias: hush.c has no arithmetic at
	# all before 1.19.4 (zero `arith` references; $(( )) expands to nothing),
	# so there is no symbol to enable and nothing we could restore.
	# Note: the "which shell is aliased to sh" choice (SH_IS_ASH/HUSH/NONE) is
	# left at allnoconfig's default and never set here. Forcing a choice member
	# via sed leaves two members =y, which makes oldconfig re-prompt the choice
	# and abort on the build's closed stdin. The alias is irrelevant anyway: the
	# binary is copied to bin/ash and invoked directly (applet = argv[0]).
	setConfs='
		CONFIG_STATIC=y
		CONFIG_LAST_SUPPORTED_WCHAR=0
		CONFIG_ASH=y
		CONFIG_ASH_ALIAS=y
		CONFIG_ASH_CMDCMD=y
		CONFIG_ASH_ECHO=y
		CONFIG_ASH_BUILTIN_ECHO=y
		CONFIG_ASH_PRINTF=y
		CONFIG_ASH_BUILTIN_PRINTF=y
		CONFIG_ASH_TEST=y
		CONFIG_ASH_BUILTIN_TEST=y
		CONFIG_ASH_INTERNAL_GLOB=y
		CONFIG_ASH_JOB_CONTROL=y
		CONFIG_ASH_RANDOM_SUPPORT=y
		CONFIG_ASH_GETOPTS=y
		CONFIG_ASH_HELP=y
		CONFIG_ASH_BASH_COMPAT=y
		CONFIG_ASH_BASH_NOT_FOUND_HOOK=y
		CONFIG_ASH_EXPAND_PRMT=y
		CONFIG_ASH_IDLE_TIMEOUT=y
		CONFIG_ASH_MAIL=y
		CONFIG_ECHO=y
		CONFIG_TEST=y
		CONFIG_FEATURE_SH_MATH=y
		CONFIG_SH_MATH_SUPPORT=y
		CONFIG_ASH_MATH_SUPPORT=y
		CONFIG_FEATURE_SH_MATH_64=y
		CONFIG_SH_MATH_SUPPORT_64=y
		CONFIG_ASH_MATH_SUPPORT_64=y
		CONFIG_FEATURE_SH_MATH_BASE=y
		CONFIG_FEATURE_SH_READ_FRAC=y
		CONFIG_FEATURE_SH_HISTFILESIZE=y
		CONFIG_FEATURE_EDITING=y
		CONFIG_FEATURE_EDITING_MAX_LEN=1024
		CONFIG_FEATURE_EDITING_HISTORY=1024
		CONFIG_FEATURE_EDITING_VI=y
		CONFIG_FEATURE_EDITING_SAVEHISTORY=y
		CONFIG_FEATURE_REVERSE_SEARCH=y
		CONFIG_FEATURE_TAB_COMPLETION=y
		CONFIG_FEATURE_EDITING_FANCY_PROMPT=y
		CONFIG_FEATURE_EDITING_WINCH=y
		CONFIG_UNICODE_SUPPORT=y
		CONFIG_FEATURE_CHECK_UNICODE_IN_ENV=y
		CONFIG_UNICODE_COMBINING_WCHARS=y
		CONFIG_UNICODE_WIDE_WCHARS=y
		CONFIG_SUBST_WCHAR=63
	'

	# Configurations to explicitly disable.
	unsetConfs='
		CONFIG_ASH_OPTIMIZE_FOR_SIZE
	'

	# Pre-1.18 busybox bakes the build clock into the version banner via
	# BUILDTIME (Rules.mak runs `date`, scripts/config/confdata.c reads
	# getenv("BUILDTIME")), which KBUILD_BUILD_TIMESTAMP does not pin. A
	# make command-line override beats Rules.mak's `:=` and is exported to
	# the config tool; on modern busybox BUILDTIME is unused, so this is a
	# no-op there. Keep it on every make call so config and compile agree.
	#
	# FEATURE_USERNAME_COMPLETION is deliberately NOT enabled: old busybox
	# (e.g. 1.21.1) implements complete_username() with getpwent_r(), a glibc
	# extension musl lacks, so the static musl link fails. Plain
	# FEATURE_TAB_COMPLETION (files/commands) needs no such symbol.
	BUILDTIME="1970.01.01-00:00+0000"

	# Start with minimal config (all disabled)
	make allnoconfig BUILDTIME="$BUILDTIME"

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
	make oldconfig BUILDTIME="$BUILDTIME"

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

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CFLAGS="-Os -frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"

	make \
		CROSS_COMPILE="${SHVR_MCM_OUTPUT}/bin/$(shvr_musl_target)-" \
		KBUILD_BUILD_TIMESTAMP="Thu Jan  1 00:00:01 UTC 1970" \
		KBUILD_BUILD_USER="builder" \
		KBUILD_BUILD_HOST="builder" \
		BUILDTIME="$BUILDTIME"

	unset SOURCE_DATE_EPOCH TZ CFLAGS LDFLAGS

	mkdir -p "${SHVR_DIR_OUT}/ash_${version}/bin"
	cp "busybox" "${SHVR_DIR_OUT}/ash_${version}/bin/ash"

	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/ash_${version}/bin/ash"
	touch -d "@1" "${SHVR_DIR_OUT}/ash_${version}/bin/ash"
	chmod 755 "${SHVR_DIR_OUT}/ash_${version}/bin/ash"

	"${SHVR_DIR_OUT}/ash_${version}/bin/ash" -c "echo busybox ash version $version"
}

shvr_deps_ash ()
{
	shvr_versioninfo_ash "$1"
	apt-get -y install \
		curl bzip2 make patch
}