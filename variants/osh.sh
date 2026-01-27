#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_osh ()
{
	cat <<-@
		osh_0.37.0
		osh_0.36.0
	@
}

shvr_targets_osh ()
{
	cat <<-@
		osh_0.37.0
		osh_0.36.0
		osh_0.35.0
		osh_0.34.0
		osh_0.33.0
		osh_0.32.0
		osh_0.31.0
		osh_0.30.0
		osh_0.29.0
		osh_0.28.0
		osh_0.27.0
		osh_0.26.0
		osh_0.25.0
	@
}

shvr_versioninfo_osh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/osh/${version}"
}

shvr_download_osh ()
{
	shvr_versioninfo_osh "$1"

	mkdir -p "${SHVR_DIR_SRC}/osh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://oils.pub/download/oils-for-unix-${version}.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_osh ()
{
	shvr_versioninfo_osh "$1"

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

	# Build with reproducible flags
	# Use fixed source date epoch and disable compiler timestamp features
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export LDFLAGS="-Wl,--build-id=none"
	export RANLIB="ranlib -D"
	export AR="ar -D"

	./configure \
		--without-readline \
		--prefix="${SHVR_DIR_OUT}/osh_$version"

	_build/oils.sh

	unset SOURCE_DATE_EPOCH TZ LDFLAGS RANLIB AR

	mkdir -p "${SHVR_DIR_OUT}/osh_${version}/bin"
	cp "_bin/cxx-opt-sh/oils-for-unix" "${SHVR_DIR_OUT}/osh_$version/bin/osh"

	# Strip binary to ensure reproducible output
	strip --strip-all "${SHVR_DIR_OUT}/osh_${version}/bin/osh"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/osh_${version}/bin/osh"
	chmod 755 "${SHVR_DIR_OUT}/osh_${version}/bin/osh"

	"${SHVR_DIR_OUT}/osh_${version}/bin/osh" -c "echo osh version $version"
}

shvr_deps_osh ()
{
	shvr_versioninfo_osh "$1"
	apt-get -y install \
		wget gcc g++ make binutils
}
