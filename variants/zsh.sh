#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/ncurses.sh"

shvr_static_zsh ()
{
	return 0
}

shvr_current_zsh ()
{
	shvr_read_versions zsh current
}

shvr_targets_zsh ()
{
	shvr_read_versions zsh all
}

shvr_update_zsh ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/sourceforge.sh"
	shvr_versions_from_sourceforge zsh /zsh |
		shvr_merge_versions zsh
}

shvr_series_zsh ()
{
	shvr_versioninfo_zsh "$1" || return 1
	printf '%s.%s\n' "${version_major}" "${version_minor}"
}

shvr_versioninfo_zsh ()
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

	build_srcdir="${SHVR_DIR_SRC}/zsh/${version}"
}

shvr_download_zsh ()
{
	shvr_versioninfo_zsh "$1"

	mkdir -p "${SHVR_DIR_SRC}/zsh"

	if
		{ test "$version_major" -gt 4 && test "${version_minor}" -gt 0; } ||
		test "$version_major" -gt 5
	then
		if ! test -f "${build_srcdir}.tar.xz"
		then
			shvr_fetch "https://downloads.sourceforge.net/project/zsh/zsh/$version/zsh-$version.tar.xz" "${build_srcdir}.tar.xz"
		fi
	else
		if ! test -f "${build_srcdir}.tar.gz"
		then
			shvr_fetch "https://downloads.sourceforge.net/project/zsh/zsh/$version/zsh-$version.tar.gz" "${build_srcdir}.tar.gz"
		fi
	fi

	shvr_download_ncurses
}

shvr_build_zsh ()
{
	shvr_versioninfo_zsh "$1"

	# Build static ncurses first
	shvr_build_ncurses

	mkdir -p "${build_srcdir}"

	if
		{ test "$version_major" -gt 4 && test "${version_minor}" -gt 0; } ||
		test "$version_major" -gt 5
	then
		shvr_untar "${build_srcdir}.tar.xz" "${build_srcdir}"
	else
		shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"
	fi

	cd "${build_srcdir}"

	if test -d "${SHVR_DIR_SELF}/patches/zsh/$version"
	then
		find "${SHVR_DIR_SELF}/patches/zsh/$version" -type f -o -type l | sort | while read -r patch_file
		do patch -p0 < "$patch_file"
		done
	fi

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC="$(shvr_musl_cc) -static"
	export AR="$(shvr_musl_ar)"
	export RANLIB="$(shvr_musl_ranlib)"
	export CFLAGS="-frandom-seed=1 $(shvr_ncurses_cflags)"
	export LDFLAGS="-Wl,--build-id=none $(shvr_ncurses_ldflags)"
	export CPPFLAGS="$(shvr_ncurses_cflags)"

	# zsh <5.0 mathfunc.c calls the deprecated gamma() (a historical alias for
	# lgamma, i.e. log-gamma) unconditionally; musl dropped that symbol, so
	# statically linking zsh/mathfunc fails at link with "undefined reference to
	# gamma". Map the call to lgamma -- it is the only `gamma(` token in the tree
	# and the "gamma" math-function name is a string literal, so users still call
	# gamma() and get the same value. 5.0+ guards the call on a configure probe
	# (HAVE_GAMMA), which fails cleanly under musl, so this is only needed for 4.x.
	if test "$version_major" -lt 5
	then export CFLAGS="${CFLAGS} -Dgamma=lgamma"
	fi

	./Util/preconfig

	# Replace config.sub/config.guess with modern versions that recognize musl
	# and non-x86 build machines (the bundled config.guess predates aarch64, so
	# it cannot self-identify an arm64 build host).
	cp "$(automake --print-libdir)/config.sub" .
	cp "$(automake --print-libdir)/config.guess" .

	# Multibyte/Unicode: --enable-multibyte (zsh 5.0+) is on by default in 5.x but
	# pinned here; --enable-unicode9 (5.3.1+) compiles in the in-tree Unicode-9
	# width tables (emoji/CJK widths) and needs no external library. Both are
	# unknown to older configure but autoconf accepts unknown --enable silently,
	# so the version gates are for cleanliness, not safety.
	extra_flags=
	if test "$version_major" -ge 5
	then extra_flags="--enable-multibyte"
	fi
	if test "$version_major" -gt 5 ||
		{ test "$version_major" -eq 5 && test "$version_minor" -ge 3; }
	then extra_flags="$extra_flags --enable-unicode9"
	fi

	./configure \
		--host="$(shvr_musl_target)" \
		--prefix="${SHVR_DIR_OUT}/zsh_$version" \
		--disable-dynamic \
		--with-tcsetpgrp \
		--with-term-lib="ncurses" \
		$extra_flags

	# A fully static binary cannot dlopen modules, so configure marks every
	# optional module link=no (dropped). Flip the buildable, libc-only ones to
	# link=static so they are compiled into the binary and usable via zmodload:
	# mathfunc (float math fns), regex (=~), system (syscall/flock), stat, mapfile,
	# files (zf_*), zselect, zpty, net/socket+net/tcp, zftp, clone, param/private,
	# zprof, watch, deltochar, nearcolor. (datetime, zle, complete, etc. are
	# already link=static.) Modules needing libraries we do not ship are left
	# link=no: cap->libcap, db/gdbm->libgdbm, pcre->libpcre2, and zsh/curses needs
	# wide-char ncurses (ours is --disable-widec). The sed no-ops on versions that
	# lack a given module, so one list is safe across the whole range; make prep
	# regenerates the module tables from the edited config.modules.
	for mod in mathfunc regex stat system mapfile files zselect zpty \
		net/socket net/tcp zftp clone param/private zprof watch deltochar nearcolor
	do
		sed -i "\\#name=zsh/${mod} #s/link=no/link=static/" config.modules
	done
	make prep

	# Single-threaded build for deterministic ordering
	make

	unset SOURCE_DATE_EPOCH TZ CC CFLAGS LDFLAGS CPPFLAGS RANLIB AR

	mkdir -p "${SHVR_DIR_OUT}/zsh_${version}/bin"
	cp "Src/zsh" "${SHVR_DIR_OUT}/zsh_$version/bin"

	# Strip binary to ensure reproducible output
	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/zsh_${version}/bin/zsh"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/zsh_${version}/bin/zsh"
	chmod 755 "${SHVR_DIR_OUT}/zsh_${version}/bin/zsh"

	"${SHVR_DIR_OUT}/zsh_${version}/bin/zsh" --version
}

shvr_deps_zsh ()
{
	shvr_versioninfo_zsh "$1"
	if
		{ test "$version_major" -gt 4 && test "${version_minor}" -gt 0; } ||
		test "$version_major" -gt 5
	then
		apt-get -y install \
			curl autoconf automake xz-utils
	else
		apt-get -y install \
			curl autoconf automake
	fi
}
