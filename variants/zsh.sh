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
	cat <<-@
		zsh_5.9
		zsh_5.8.1
	@
}

shvr_targets_zsh ()
{
	cat <<-@
		zsh_5.9
		zsh_5.8.1
		zsh_5.7.1
		zsh_5.6.2
		zsh_5.5.1
		zsh_5.4.2
		zsh_5.3.1
		zsh_5.2
		zsh_5.1.1
		zsh_5.0.8
		zsh_4.2.7
	@
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

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC="$(shvr_musl_cc) -static"
	export AR="$(shvr_musl_ar)"
	export RANLIB="$(shvr_musl_ranlib)"
	export CFLAGS="-frandom-seed=1 $(shvr_ncurses_cflags)"
	export LDFLAGS="-Wl,--build-id=none $(shvr_ncurses_ldflags)"
	export CPPFLAGS="$(shvr_ncurses_cflags)"

	./Util/preconfig

	# Replace config.sub with a modern version that recognizes musl
	cp "$(automake --print-libdir)/config.sub" .

	./configure \
		--host=x86_64-linux-musl \
		--prefix="${SHVR_DIR_OUT}/zsh_$version" \
		--disable-dynamic \
		--with-tcsetpgrp \
		--with-term-lib="ncurses"

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
