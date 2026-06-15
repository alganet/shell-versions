#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"

shvr_static_posh ()
{
	return 0
}

shvr_current_posh ()
{
	shvr_read_versions posh current
}

shvr_targets_posh ()
{
	shvr_read_versions posh all
}

shvr_update_posh ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/git_tags.sh"
	shvr_versions_from_git_tags \
		"https://salsa.debian.org/clint/posh.git" \
		'debian/([0-9.]+)' |
		shvr_merge_versions posh
}

shvr_series_posh ()
{
	shvr_versioninfo_posh "$1" || return 1
	series_rest="${version#*.}"
	printf '%s.%s\n' "${version%%.*}" "${series_rest%%.*}"
}

shvr_versioninfo_posh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/posh/${version}"
}

shvr_download_posh ()
{
	shvr_versioninfo_posh "$1"

	mkdir -p "${SHVR_DIR_SRC}/posh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://salsa.debian.org/clint/posh/-/archive/debian/$version/posh-debian-$version.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_posh ()
{
	shvr_versioninfo_posh "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	autoreconf -fi

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC="$(shvr_musl_cc) -static"
	export AR="$(shvr_musl_ar)"
	export RANLIB="$(shvr_musl_ranlib)"
	export CFLAGS="-frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"

	./configure \
		--host=x86_64-linux-musl \
		--prefix="${SHVR_DIR_OUT}/posh_$version"

	make

	unset SOURCE_DATE_EPOCH TZ CC AR RANLIB CFLAGS LDFLAGS

	mkdir -p "${SHVR_DIR_OUT}/posh_${version}/bin"
	cp "posh" "${SHVR_DIR_OUT}/posh_$version/bin"

	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/posh_${version}/bin/posh"
	touch -d "@1" "${SHVR_DIR_OUT}/posh_${version}/bin/posh"
	chmod 755 "${SHVR_DIR_OUT}/posh_${version}/bin/posh"

	"${SHVR_DIR_OUT}/posh_${version}/bin/posh" -c "echo posh version $version"
}

shvr_deps_posh ()
{
	shvr_versioninfo_posh "$1"
	apt-get -y install \
		curl make autoconf automake
}
