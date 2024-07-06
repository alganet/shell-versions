#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_zsh ()
{
	cat <<-@
		zsh_5.9
		zsh_5.8.1
		zsh_appl-100.120.1
		zsh_appl-100
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
		zsh_appl-100.120.1
		zsh_appl-100
		zsh_appl-97
		zsh_appl-94
		zsh_appl-92
		zsh_appl-90
		zsh_appl-87
		zsh_appl-84.120.1
		zsh_appl-84.100.1
		zsh_appl-84
	@
}

shvr_build_zsh ()
{
	version="$1"
	fork_name="${1%%-*}"
	fork_version="${1#*-}"
	build_srcdir="${SHVR_DIR_SRC}/zsh/${version}"
	mkdir -p "${build_srcdir}"

	case "$fork_name" in
		*'appl')
			build_innerdir="zsh"
			archiver="gz"
			version_major=-1
			version_url="https://github.com/apple-oss-distributions/zsh/archive/refs/tags/zsh-$fork_version.tar.gz"

			apt-get -y install \
				wget gcc make autoconf libtinfo-dev
			;;
		*)
			build_innerdir="."
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

			if
				test "$version_major" -gt 4 -a "${version_minor}" -gt 0 ||
				test "$version_major" -gt 5
			then
				archiver="xz"
				apt-get -y install \
					wget gcc make autoconf libtinfo-dev xz-utils
			else
				archiver="gz"
				apt-get -y install \
					wget gcc make autoconf libtinfo-dev
			fi

			version_url="https://downloads.sourceforge.net/project/zsh/zsh/$version/zsh-$version.tar.$archiver"
			;;
	esac
	wget -O "${build_srcdir}.tar.$archiver" "$version_url"
	tar --extract \
		--file="${build_srcdir}.tar.$archiver" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}/${build_innerdir}"

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
