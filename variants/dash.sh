#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_dash ()
{
	cat <<-@
		dash_0.5.13
		dash_0.5.12
	@
}

shvr_targets_dash ()
{
	cat <<-@
		dash_0.5.13
		dash_0.5.12
		dash_0.5.11.5
		dash_0.5.10.2
		dash_0.5.9.1
		dash_0.5.8
		dash_0.5.7
		dash_0.5.6.1
		dash_0.5.5.1
	@
}

shvr_versioninfo_dash ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/dash/${version}"
}

shvr_download_dash ()
{
	shvr_versioninfo_dash "$1"

	mkdir -p "${SHVR_DIR_SRC}/dash"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-$version.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_dash ()
{
	shvr_versioninfo_dash "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	# TODO remove this dependency
	build_arch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"

	if test -f ./autogen.sh
	then
		./autogen.sh
	else
		aclocal
		autoheader
		automake --add-missing
		autoconf
	fi

	# Build with reproducible flags
	# Use fixed source date epoch and disable compiler timestamp features
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CFLAGS="-frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"
	export RANLIB="ranlib -D"
	export AR="ar -D"

	./configure \
		--build="$build_arch" \
		--prefix="${SHVR_DIR_OUT}/dash_$version"

	# Single-threaded build for deterministic ordering
	make

	unset SOURCE_DATE_EPOCH TZ CFLAGS LDFLAGS RANLIB AR

	mkdir -p "${SHVR_DIR_OUT}/dash_${version}/bin"
	cp "src/dash" "${SHVR_DIR_OUT}/dash_$version/bin/dash"

	# Strip binary to ensure reproducible output
	strip --strip-all "${SHVR_DIR_OUT}/dash_${version}/bin/dash"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/dash_${version}/bin/dash"
	chmod 755 "${SHVR_DIR_OUT}/dash_${version}/bin/dash"

	"${SHVR_DIR_OUT}/dash_${version}/bin/dash" -c "echo dash version $version"
}

shvr_deps_dash ()
{
	shvr_versioninfo_dash "$1"
	apt-get -y install \
		curl gcc automake autoconf dpkg-dev binutils
}
