#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_posh ()
{
	cat <<-@
		posh_0.14.3
		posh_0.13.2
	@
}

shvr_targets_posh ()
{
	cat <<-@
		posh_0.14.3
		posh_0.13.2
		posh_0.12.6
	@
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

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}" \
		--owner=0 \
		--group=0 \
		--mode=go-w \
		--touch

	cd "${build_srcdir}"

	autoreconf -fi

	# Build with reproducible flags
	# Use fixed source date epoch and disable compiler timestamp features
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CFLAGS="-frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"
	export RANLIB="ranlib -D"
	export AR="ar -D"

	./configure \
		--prefix="${SHVR_DIR_OUT}/posh_$version"

	# Single-threaded build for deterministic ordering
	make

	unset SOURCE_DATE_EPOCH TZ CFLAGS LDFLAGS RANLIB AR

	mkdir -p "${SHVR_DIR_OUT}/posh_${version}/bin"
	cp "posh" "${SHVR_DIR_OUT}/posh_$version/bin"

	# Strip binary to ensure reproducible output
	strip --strip-all "${SHVR_DIR_OUT}/posh_${version}/bin/posh"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/posh_${version}/bin/posh"
	chmod 755 "${SHVR_DIR_OUT}/posh_${version}/bin/posh"

	"${SHVR_DIR_OUT}/posh_${version}/bin/posh" -c "echo posh version $version"
}

shvr_deps_posh ()
{
	shvr_versioninfo_posh "$1"
	apt-get -y install \
		curl gcc make autoconf automake binutils
}
