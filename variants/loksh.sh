#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/ncurses.sh"

shvr_static_loksh ()
{
	return 0
}

shvr_current_loksh ()
{
	shvr_read_versions loksh current
}

shvr_targets_loksh ()
{
	shvr_read_versions loksh all
}

shvr_update_loksh ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/github_releases.sh"
	shvr_versions_from_github_tags dimkr/loksh '([0-9]+\.[0-9]+(\.[0-9]+)?)' |
		shvr_merge_versions loksh
}

shvr_series_loksh ()
{
	shvr_versioninfo_loksh "$1" || return 1
	printf '%s.%s\n' "${version_major}" "${version_minor}"
}

shvr_snapshotsource_loksh ()
{
	echo "https://github.com/dimkr/loksh master"
}

shvr_versioninfo_loksh ()
{
	version="$1"

	# Before the numeric parsing below, which would reject the token (no "." in it, so
	# version_major would equal version -> return 1). The infinite version makes
	# shvr_loksh_premeson false, i.e. the modern meson build.
	if shvr_is_snapshot "$version"
	then
		version_major=99
		version_minor=99
		version_patch=0
		build_srcdir="${SHVR_DIR_SRC}/loksh/${version}"
		return 0
	fi

	version_major="${version%%\.*}"

	if test "$version" = "$version_major"
	then return 1
	fi
	version_minor="${version#$version_major\.}"
	version_patch="${version_minor#*\.}"
	if test "$version_patch" = "$version_minor"
	then version_patch="0"
	else version_minor="${version_minor%\.*}"
	fi

	build_srcdir="${SHVR_DIR_SRC}/loksh/${version}"
}

# True for the pre-meson era (< 6.7.5): those tags ship a plain Makefile and no
# meson.build, and upstream published no release tarball for them, so they are
# fetched from the github archive and built via the Makefile path below. 6.7.5+
# carry meson.build and a release tarball.
shvr_loksh_premeson ()
{
	test "$version_major" -lt 6 ||
		{ test "$version_major" -eq 6 && test "$version_minor" -lt 7; }
}

shvr_download_loksh ()
{
	shvr_versioninfo_loksh "$1"

	mkdir -p "${SHVR_DIR_SRC}/loksh"

	if ! test -f "${build_srcdir}.tar.xz"
	then
		if shvr_is_snapshot "$version"
		then
			shvr_snapshot_fetch_git loksh "$version" "${build_srcdir}.tar.xz" "loksh-${version}"
		elif shvr_loksh_premeson
		then
			# No release asset for these tags; the github archive tag tarball
			# ships the full Makefile-based tree. Saved as .tar.xz so the build
			# untar finds it (tar autodetects the gzip payload).
			shvr_fetch "https://github.com/dimkr/loksh/archive/refs/tags/$version.tar.gz" "${build_srcdir}.tar.xz"
		else
			shvr_fetch "https://github.com/dimkr/loksh/releases/download/$version/loksh-$version.tar.xz" "${build_srcdir}.tar.xz"
		fi
	fi

	# loksh's meson.build links ncurses when found and otherwise compiles a
	# reduced build (-DSMALL); we supply the in-tree static ncurses so the full
	# build (persistent history, $MAILCHECK, $KSH_VERSION, prompt \v, Ctrl-L) is
	# kept.
	shvr_download_ncurses
}

shvr_build_loksh ()
{
	shvr_versioninfo_loksh "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.xz" "${build_srcdir}"

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC

	# Pre-meson tags (< 6.7.5) ship a plain Makefile (BIN_NAME ?= ksh) and a
	# pre-generated config.h with the emacs/vi editor enabled, so they pull in
	# <term.h>/<curses.h> and need the terminfo library at link time. Build the
	# in-tree static ncurses and feed its include/lib flags through CFLAGS/LDFLAGS;
	# the Makefile honours CC/CFLAGS/LDFLAGS. (The meson path below is unchanged
	# for 6.7.5+.)
	if shvr_loksh_premeson
	then
		shvr_build_ncurses
		cd "${build_srcdir}"

		# emacs.c includes <sys/queue.h> for the TAILQ_* macros the kill ring uses.
		# The tree ships OpenBSD's full queue.h, which musl cannot compile; replace
		# it with a TAILQ-only shim carrying just what loksh calls. The Makefile's
		# `-isystem .` is what resolves the include to this file.
		#
		# A payload rather than a patch: this replaces the header wholesale (the
		# shipped one is ~650 lines and differs across the band), so a diff would
		# be a delete-everything/add-35 per version and say nothing a copy does
		# not. Same reasoning as ksh's dylink stub.
		cp "${SHVR_DIR_SELF}/payloads/loksh/sys-queue-tailq-shim.h" "${build_srcdir}/sys/queue.h"

		export CC="$(shvr_musl_cc) -static"
		# gcc 10+ defaults to -fno-common, so the pre-meson tree's tentative-definition
		# globals (e.g. `got_sigwinch`, in both main.c and edit.c) collide at link
		# ("multiple definition"). -fcommon restores the gcc-9 merge behavior.
		export CFLAGS="-fcommon -frandom-seed=1 $(shvr_ncurses_cflags)"
		# The Makefile sources -lncurses from `pkg-config --libs ncurses`, which
		# is empty for the in-tree (pkg-config-less) ncurses, so add the library
		# explicitly -- after the objects in the link line (LDFLAGS is appended
		# last) so the static terminfo symbols (cur_term/tputs/setupterm) resolve.
		export LDFLAGS="-Wl,--build-id=none $(shvr_ncurses_ldflags) -lncurses"

		# Pass these through the ENVIRONMENT, not `make VAR=...`: the Makefiles
		# extend their own flags with `CFLAGS += -I. ...` (6.x uses `override`,
		# 5.x a plain `+=`), and a command-line assignment would disable that
		# append and drop the tree's own `-I.`/`-isystem .` (which is what locates
		# the sys/queue.h shim) and `-DEMACS -DVI`. An environment value is the
		# base that `+=` adds to, so both flag sets survive.
		make

		unset SOURCE_DATE_EPOCH TZ CC CFLAGS LDFLAGS

		mkdir -p "${SHVR_DIR_OUT}/loksh_${version}/bin"
		cp "ksh" "${SHVR_DIR_OUT}/loksh_$version/bin/loksh"

		"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"
		touch -d "@1" "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"
		chmod 755 "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"

		"${SHVR_DIR_OUT}/loksh_${version}/bin/loksh" -c "echo loksh version $version"
		return
	fi

	# Build the in-tree static ncurses so loksh's `dependency('ncurses')` resolves;
	# without it loksh compiles the -DSMALL reduced build, dropping persistent
	# history, $MAILCHECK, the $KSH_VERSION/$SH_VERSION variables, the \v/\V prompt
	# escape and Ctrl-L. meson's curses dependency only tries pkg-config and cmake
	# (no compiler probe), so we hand-write an ncurses.pc pointing at the in-tree
	# build and put it on PKG_CONFIG_PATH -- this leaves common/ncurses.sh (shared
	# with bash/zsh/oksh) untouched. The cross-file also carries the include/lib
	# paths so the static libncurses.a is found at link time.
	shvr_build_ncurses
	cd "${build_srcdir}"

	# Hand-written pkg-config file for the in-tree static ncurses.
	pkgconfig_dir="${build_srcdir}/.shvr_pkgconfig"
	mkdir -p "${pkgconfig_dir}"
	cat > "${pkgconfig_dir}/ncurses.pc" <<-PC
		prefix=${SHVR_NCURSES_PREFIX}
		Name: ncurses
		Description: in-tree static ncurses
		Version: ${SHVR_NCURSES_VERSION}
		Cflags: -I\${prefix}/include -I\${prefix}/include/ncurses
		Libs: -L\${prefix}/lib -lncurses
	PC
	# PKG_CONFIG_LIBDIR replaces the default search path (correct for a cross
	# build: only our ncurses.pc is visible); PKG_CONFIG_PATH covers meson
	# versions that read it instead.
	export PKG_CONFIG_PATH="${pkgconfig_dir}"
	export PKG_CONFIG_LIBDIR="${pkgconfig_dir}"

	# Render the ncurses include/lib flags as meson array elements.
	nc_cargs=$(for f in $(shvr_ncurses_cflags); do printf ", '%s'" "$f"; done)
	nc_largs=$(for f in $(shvr_ncurses_ldflags); do printf ", '%s'" "$f"; done)

	# Create meson cross-file for musl static build
	cat > musl-cross.txt <<-EOF
		[binaries]
		c = '$(shvr_musl_cc)'
		ar = '$(shvr_musl_ar)'
		strip = '$(shvr_musl_strip)'
		pkgconfig = 'pkg-config'

		[built-in options]
		c_args = ['-static', '-frandom-seed=1'${nc_cargs}]
		c_link_args = ['-static', '-Wl,--build-id=none'${nc_largs}]

		[host_machine]
		system = 'linux'
		cpu_family = '$(shvr_meson_cpu)'
		cpu = '$(shvr_meson_cpu)'
		endian = 'little'
	EOF

	meson \
		--prefix="${SHVR_DIR_OUT}/loksh_$version" \
		--cross-file musl-cross.txt \
		build

	ninja -C build

	unset SOURCE_DATE_EPOCH TZ PKG_CONFIG_PATH PKG_CONFIG_LIBDIR

	mkdir -p "${SHVR_DIR_OUT}/loksh_${version}/bin"
	cp "build/ksh" "${SHVR_DIR_OUT}/loksh_$version/bin/loksh"

	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"
	touch -d "@1" "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"
	chmod 755 "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"

	"${SHVR_DIR_OUT}/loksh_${version}/bin/loksh" -c "echo loksh version $version"
}

shvr_deps_loksh ()
{
	shvr_versioninfo_loksh "$1"
	apt-get -y install \
		curl meson ninja-build xz-utils pkg-config
}
