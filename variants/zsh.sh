#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

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
}

shvr_build_zsh ()
{
	shvr_versioninfo_zsh "$1"

	mkdir -p "${build_srcdir}"

	if
		{ test "$version_major" -gt 4 && test "${version_minor}" -gt 0; } ||
		test "$version_major" -gt 5
	then
		tar --extract \
			--file="${build_srcdir}.tar.xz" \
			--strip-components=1 \
			--directory="${build_srcdir}" \
			--owner=0 \
			--group=0 \
			--mode=go-w \
			--touch
	else
		tar --extract \
			--file="${build_srcdir}.tar.gz" \
			--strip-components=1 \
			--directory="${build_srcdir}" \
			--owner=0 \
			--group=0 \
			--mode=go-w \
			--touch
	fi

	cd "${build_srcdir}"

	# Build with reproducible flags
	# Use fixed source date epoch and disable compiler timestamp features
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC=gcc-12
	export CFLAGS='-frandom-seed=1 -ffile-prefix-map='"${build_srcdir}"'=.'
	export LDFLAGS='-Wl,--build-id=none'
	export RANLIB='ranlib -D'
	export AR='ar -D'

	./Util/preconfig
	./configure \
		--prefix="${SHVR_DIR_OUT}/zsh_$version" \
		--disable-dynamic \
		--with-tcsetpgrp

	# Single-threaded build for deterministic ordering
	make

	unset SOURCE_DATE_EPOCH TZ CC CFLAGS LDFLAGS RANLIB AR

	mkdir -p "${SHVR_DIR_OUT}/zsh_${version}/bin"
	cp "Src/zsh" "${SHVR_DIR_OUT}/zsh_$version/bin"

	# Strip binary to ensure reproducible output
	strip --strip-all "${SHVR_DIR_OUT}/zsh_${version}/bin/zsh"

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
			curl gcc-12 make autoconf libtinfo-dev xz-utils binutils
	else
		apt-get -y install \
			curl gcc-12 make autoconf libtinfo-dev binutils
	fi
}

