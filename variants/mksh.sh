#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_mksh ()
{
	cat <<-@
		mksh_R59c
		mksh_R58
	@
}

shvr_targets_mksh ()
{
	cat <<-@
		mksh_R59c
		mksh_R58
		mksh_R57
		mksh_R56c
		mksh_R55
		mksh_R54
		mksh_R53a
		mksh_R52c
		mksh_R51
		mksh_R50f
		mksh_R49
		mksh_R48b
		mksh_R47
		mksh_R46
		mksh_R45
	@
}

shvr_versioninfo_mksh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/mksh/${version}"
}

shvr_download_mksh ()
{
	shvr_versioninfo_mksh "$1"

	mkdir -p "${SHVR_DIR_SRC}/mksh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://github.com/MirBSD/mksh/archive/refs/tags/mksh-$version.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_mksh ()
{
	shvr_versioninfo_mksh "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	# Build with reproducible flags
	# Use fixed source date epoch and disable compiler timestamp features
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CFLAGS="-frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"
	export RANLIB="ranlib -D"
	export AR="ar -D"

	sh ./Build.sh

	unset SOURCE_DATE_EPOCH TZ CFLAGS LDFLAGS RANLIB AR

	mkdir -p "${SHVR_DIR_OUT}/mksh_${version}/bin"
	cp "mksh" "${SHVR_DIR_OUT}/mksh_$version/bin"

	# Strip binary to ensure reproducible output
	strip --strip-all "${SHVR_DIR_OUT}/mksh_${version}/bin/mksh"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/mksh_${version}/bin/mksh"
	chmod 755 "${SHVR_DIR_OUT}/mksh_${version}/bin/mksh"

	"${SHVR_DIR_OUT}/mksh_${version}/bin/mksh" -c "echo mksh version $version"
}

shvr_deps_mksh ()
{
	shvr_versioninfo_mksh "$1"
	apt-get -y install \
		curl gcc make binutils
}
