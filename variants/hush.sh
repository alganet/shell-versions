#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/busybox.sh"
. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"

shvr_static_hush ()
{
	return 0
}

shvr_current_hush ()
{
	shvr_current_busybox "$@" | sed -e 's/^busybox_/hush_/'
}

shvr_targets_hush ()
{
	shvr_targets_busybox "$@" | sed -e 's/^busybox_/hush_/'
}

shvr_update_hush ()
{
	shvr_update_busybox
}

# hush carries no versions/hush.all; its versions (and their dates) are busybox's.
shvr_versionsource_hush ()
{
	echo busybox
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

	# ash and hush share build_srcdir (busybox/<version>). Remove any prior
	# extraction/build tree so a fresh source is unpacked every time; otherwise
	# building both shells of one version in a single container (e.g.
	# `shvr.sh build ash_X hush_X`, as the Dockerfile does) leaves stale objects
	# that contaminate the second build and break reproducibility on old busybox.
	rm -rf "${build_srcdir}"
	mkdir -p "${build_srcdir}"

	mkdir -p /usr/src/busybox
	shvr_untar "${build_srcdir}.tar.bz2" "${build_srcdir}"

	cd "${build_srcdir}"

	# Pre-kbuild-2.6.36 trees (1.3..1.16) carry mixed implicit/normal Makefile
	# rules that GNU make >= 4.3 rejects; drop the bare normal targets so the
	# Makefile parses. No-op on newer trees and the 1.2.x island.
	shvr_busybox_fix_makefile

	# Configurations to enable for hush-focused builds.
	# Includes hush features, static linking, and individual applet support.
	#
	# Renamed-symbol handling: arithmetic is gated by SH_MATH_SUPPORT (<=1.26.2)
	# vs FEATURE_SH_MATH (>=1.27.2), and the sh==hush choice by
	# FEATURE_SH_IS_HUSH (<=1.21.1) vs SH_IS_HUSH. allnoconfig + sed + oldconfig
	# silently drops symbols absent from a given version, so we list BOTH names;
	# whichever exists is applied. Per-builtin HUSH_* symbols first appear in
	# 1.27.2; on older hush echo/printf/test are unconditional, so no aliasing is
	# needed for those. Without the math aliases, hush has no $(( )) at all.
	# Note: the "which shell is aliased to sh" choice (SH_IS_ASH/HUSH/NONE) is
	# left at allnoconfig's default and never set here. Forcing a choice member
	# via sed leaves two members =y, which makes oldconfig re-prompt the choice
	# and abort on the build's closed stdin. The alias is irrelevant anyway: the
	# binary is copied to bin/hush and invoked directly (applet = argv[0]).
	setConfs='
		CONFIG_STATIC=y
		CONFIG_LAST_SUPPORTED_WCHAR=0
		CONFIG_HUSH=y
		CONFIG_HUSH_CASE=y
		CONFIG_HUSH_COMMAND=y
		CONFIG_HUSH_ECHO=y
		CONFIG_HUSH_PRINTF=y
		CONFIG_HUSH_TEST=y
		CONFIG_HUSH_EXPORT=y
		CONFIG_HUSH_EXPORT_N=y
		CONFIG_HUSH_READONLY=y
		CONFIG_HUSH_FUNCTIONS=y
		CONFIG_HUSH_FUNCTION_KEYWORD=y
		CONFIG_HUSH_LOCAL=y
		CONFIG_HUSH_ALIAS=y
		CONFIG_HUSH_IF=y
		CONFIG_HUSH_INTERACTIVE=y
		CONFIG_HUSH_SAVEHISTORY=y
		CONFIG_HUSH_JOB=y
		CONFIG_HUSH_KILL=y
		CONFIG_HUSH_LOOPS=y
		CONFIG_HUSH_MODE_X=y
		CONFIG_HUSH_RANDOM_SUPPORT=y
		CONFIG_HUSH_READ=y
		CONFIG_HUSH_SET=y
		CONFIG_HUSH_TICK=y
		CONFIG_HUSH_TRAP=y
		CONFIG_HUSH_TYPE=y
		CONFIG_HUSH_TIMES=y
		CONFIG_HUSH_HELP=y
		CONFIG_HUSH_GETOPTS=y
		CONFIG_HUSH_ULIMIT=y
		CONFIG_HUSH_UMASK=y
		CONFIG_HUSH_UNSET=y
		CONFIG_HUSH_WAIT=y
		CONFIG_HUSH_BASH_COMPAT=y
		CONFIG_HUSH_BRACE_EXPANSION=y
		CONFIG_HUSH_LINENO_VAR=y
		CONFIG_ECHO=y
		CONFIG_TEST=y
		CONFIG_FEATURE_SH_MATH=y
		CONFIG_SH_MATH_SUPPORT=y
		CONFIG_FEATURE_SH_MATH_64=y
		CONFIG_SH_MATH_SUPPORT_64=y
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

	mkdir -p "${SHVR_DIR_OUT}/hush_${version}/bin"
	cp "busybox" "${SHVR_DIR_OUT}/hush_${version}/bin/hush"

	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/hush_${version}/bin/hush"
	touch -d "@1" "${SHVR_DIR_OUT}/hush_${version}/bin/hush"
	chmod 755 "${SHVR_DIR_OUT}/hush_${version}/bin/hush"

	"${SHVR_DIR_OUT}/hush_${version}/bin/hush" -c "echo busybox hush version $version"
}

shvr_deps_hush ()
{
	shvr_versioninfo_hush "$1"
	apt-get -y install \
		curl bzip2 make
}