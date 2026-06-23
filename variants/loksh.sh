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

shvr_versioninfo_loksh ()
{
	version="$1"
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

shvr_download_loksh ()
{
	shvr_versioninfo_loksh "$1"

	mkdir -p "${SHVR_DIR_SRC}/loksh"

	if ! test -f "${build_srcdir}.tar.xz"
	then
		shvr_fetch "https://github.com/dimkr/loksh/releases/download/$version/loksh-$version.tar.xz" "${build_srcdir}.tar.xz"
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
