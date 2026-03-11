#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"

shvr_static_yash ()
{
	return 0
}

shvr_current_yash ()
{
	cat <<-@
		yash_2.60
		yash_2.59
	@
}

shvr_targets_yash ()
{
	cat <<-@
		yash_2.60
		yash_2.59
		yash_2.58.1
		yash_2.57
		yash_2.56.1
		yash_2.55
		yash_2.54
		yash_2.53
		yash_2.52
		yash_2.51
		yash_2.50
		yash_2.49
		yash_2.48
		yash_2.47
		yash_2.46
		yash_2.45
	@
}

shvr_versioninfo_yash ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/yash/${version}"
}

shvr_download_yash ()
{
	shvr_versioninfo_yash "$1"

	mkdir -p "${SHVR_DIR_SRC}/yash"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://github.com/magicant/yash/releases/download/${version}/yash-${version}.tar.xz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_yash ()
{
	shvr_versioninfo_yash "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC="$(shvr_musl_cc) -static"
	export AR="$(shvr_musl_ar)"
	export RANLIB="$(shvr_musl_ranlib)"
	export CFLAGS="-frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"

	./configure \
		--disable-nls \
		--disable-lineedit \
		--prefix="${SHVR_DIR_OUT}/yash_$version"

	make

	unset SOURCE_DATE_EPOCH TZ CC AR RANLIB CFLAGS LDFLAGS

	mkdir -p "${SHVR_DIR_OUT}/yash_${version}/bin"
	cp "yash" "${SHVR_DIR_OUT}/yash_$version/bin"

	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/yash_${version}/bin/yash"
	touch -d "@1" "${SHVR_DIR_OUT}/yash_${version}/bin/yash"
	chmod 755 "${SHVR_DIR_OUT}/yash_${version}/bin/yash"

	"${SHVR_DIR_OUT}/yash_${version}/bin/yash" -c "echo yash version $version"
}

shvr_deps_yash ()
{
	shvr_versioninfo_yash "$1"
	apt-get -y install \
		curl make xz-utils gettext
}
