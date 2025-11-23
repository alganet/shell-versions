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
		apt-get -y install \
			wget gcc make autoconf libtinfo-dev xz-utils
		tar --extract \
			--file="${build_srcdir}.tar.xz" \
			--strip-components=1 \
			--directory="${build_srcdir}"
	else
		apt-get -y install \
			wget gcc make autoconf libtinfo-dev
		tar --extract \
			--file="${build_srcdir}.tar.gz" \
			--strip-components=1 \
			--directory="${build_srcdir}"
	fi

	cd "${build_srcdir}"

	./Util/preconfig
	./configure \
		--prefix="${SHVR_DIR_OUT}/zsh_$version" \
		--disable-dynamic \
		--with-tcsetpgrp

	make -j "$(nproc)"

	mkdir -p "${SHVR_DIR_OUT}/zsh_${version}/bin"
	cp "Src/zsh" "${SHVR_DIR_OUT}/zsh_$version/bin"

	"${SHVR_DIR_OUT}/zsh_${version}/bin/zsh" --version
}

