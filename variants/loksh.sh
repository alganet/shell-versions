#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_loksh ()
{
	cat <<-@
		loksh_7.8
		loksh_7.7
	@
}

shvr_targets_loksh ()
{
	cat <<-@
		loksh_7.8
		loksh_7.7
		loksh_7.6
		loksh_7.5
		loksh_7.4
		loksh_7.3
		loksh_7.1
		loksh_7.0
		loksh_6.9
		loksh_6.8.1
		loksh_6.7.5
	@
}

shvr_versioninfo_loksh ()
{
	version="$1"
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
}

shvr_build_loksh ()
{
	shvr_versioninfo_loksh "$1"

	mkdir -p "${build_srcdir}"

	tar --extract \
		--file="${build_srcdir}.tar.xz" \
		--strip-components=1 \
		--directory="${build_srcdir}" \
		--owner=0 \
		--group=0 \
		--mode=go-w \
		--touch

	cd "${build_srcdir}"

	# Build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CFLAGS="-Os -frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"

	meson \
		--prefix="${SHVR_DIR_OUT}/loksh_$version" \
		build

	ninja -C build

	unset SOURCE_DATE_EPOCH TZ CFLAGS LDFLAGS

	mkdir -p "${SHVR_DIR_OUT}/loksh_${version}/bin"
	cp "build/ksh" "${SHVR_DIR_OUT}/loksh_$version/bin/loksh"

	# Strip binary to ensure reproducible output
	strip --strip-all "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"
	chmod 755 "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"

	"${SHVR_DIR_OUT}/loksh_${version}/bin/loksh" -c "echo loksh version $version"
}

shvr_deps_loksh ()
{
	shvr_versioninfo_loksh "$1"
	apt-get -y install \
		curl gcc meson ninja-build xz-utils binutils
}
