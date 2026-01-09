#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_oksh ()
{
	cat <<-@
		oksh_7.8
		oksh_7.7
	@
}

shvr_targets_oksh ()
{
	cat <<-@
		oksh_7.8
		oksh_7.7
		oksh_7.6
		oksh_7.5
		oksh_7.4
		oksh_7.3
		oksh_7.2
		oksh_7.1
		oksh_7.0
		oksh_6.9
		oksh_6.8.1
		oksh_6.7.1
		oksh_6.6
		oksh_6.5
	@
}

shvr_versioninfo_oksh ()
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

	build_srcdir="${SHVR_DIR_SRC}/oksh/${version}"
}

shvr_download_oksh ()
{
	shvr_versioninfo_oksh "$1"

	mkdir -p "${SHVR_DIR_SRC}/oksh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://github.com/ibara/oksh/releases/download/oksh-$version/oksh-$version.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_oksh ()
{
	shvr_versioninfo_oksh "$1"

	mkdir -p "${build_srcdir}"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	if {
		test "$version_major" -eq 7 &&
		test "$version_minor" -lt 3
	} || {
		test "$version_major" -lt 7
	}
	then
		export CFLAGS="-fcommon"
	fi

	./configure \
		--disable-curses \
		--prefix="${SHVR_DIR_OUT}/oksh_$version"

	make -j "$(nproc)"

	unset CFLAGS

	mkdir -p "${SHVR_DIR_OUT}/oksh_${version}/bin"
	cp "oksh" "${SHVR_DIR_OUT}/oksh_$version/bin"

	"${SHVR_DIR_OUT}/oksh_${version}/bin/oksh" -c "echo oksh version $version"
}

shvr_deps_oksh ()
{
	shvr_versioninfo_oksh "$1"
	apt-get -y install \
		wget gcc make
}
