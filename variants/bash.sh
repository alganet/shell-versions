#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_current_bash ()
{
	cat <<-@
		bash_5.3.9
		bash_5.2.37
	@
}

shvr_targets_bash ()
{
	cat <<-@
		bash_5.3.9
		bash_5.2.37
		bash_5.1.16
		bash_5.0.18
		bash_4.4.23
		bash_4.3.48
		bash_4.2.53
		bash_4.1.17
		bash_4.0.44
		bash_3.2.57
		bash_3.1.23
		bash_3.0.22
		bash_2.05b.13
	@
}

shvr_versioninfo_bash ()
{
	version="$1"
	version_major="${version%%\.*}"

	if test "$version" = "$version_major"
	then return 1
	fi

	version_minor="${version#$version_major\.}"
	version_patch="${version_minor#*[.-]}"

	if test "$version_patch" = "$version_minor"
	then version_patch=0
	else version_minor="${version_minor%\.*}"
	fi

	version_baseline="${version_major}.${version_minor}"
	build_srcdir="${SHVR_DIR_SRC}/bash/${version_baseline}"
}

shvr_download_bash ()
{
	shvr_versioninfo_bash "$1"

	mkdir -p "${SHVR_DIR_SRC}/bash"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://mirrors.ocf.berkeley.edu/gnu/bash/bash-${version_baseline}.tar.gz" "${build_srcdir}.tar.gz"
	fi

	mkdir -p "${build_srcdir}-patches"
	patch_i=0
	while test $patch_i -lt $version_patch
	do
		patch_i=$((patch_i + 1))
		patch_n="$(printf '%03d' "$patch_i")"
		if ! test -f "${build_srcdir}-patches/$patch_n"
		then
			url="https://mirrors.ocf.berkeley.edu/gnu/bash/bash-${version_baseline}-patches/bash${version_major}${version_minor}-${patch_n}"
			shvr_fetch "$url" "${build_srcdir}-patches/$patch_n"
		fi
	done
}

shvr_build_bash ()
{
	shvr_versioninfo_bash "$1"

	build_srcdir="${SHVR_DIR_SRC}/bash/${version_baseline}"
	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	patch_i=0
	while test $patch_i -lt $version_patch
	do
		patch_i=$((patch_i + 1))
		patch_n="$(printf '%03d' "$patch_i")"
		patch \
			--directory="${build_srcdir}" \
			--input="${build_srcdir}-patches/$patch_n" \
			--strip=0
	done
	cd "${build_srcdir}"

	if test "$version_major" -lt 5 || { test "$version_major" -eq 5 && test "${version_minor}" -lt 3; }
	then
		rm configure
		export CFLAGS_FOR_BUILD='-std=gnu90' CFLAGS='-std=gnu90' AUTOCONF='autoconf2.69'
		$AUTOCONF
		./configure \
			--prefix="${SHVR_DIR_OUT}/bash_${version}" \
			--without-bash-malloc

		# Build with reproducible flags
		# Use fixed source date epoch and disable compiler timestamp features
		export SOURCE_DATE_EPOCH=1
		export TZ=UTC
		export LDFLAGS="-Wl,--build-id=none"
		export RANLIB="ranlib -D"
		export AR="ar -D"

		make -j1

		unset SOURCE_DATE_EPOCH TZ LDFLAGS RANLIB AR CFLAGS_FOR_BUILD CFLAGS AUTOCONF
	else
		./configure \
			--prefix="${SHVR_DIR_OUT}/bash_${version}"

		# Build with reproducible flags
		# Use fixed source date epoch and disable compiler timestamp features
		export SOURCE_DATE_EPOCH=1
		export TZ=UTC
		export LDFLAGS="-Wl,--build-id=none"
		export RANLIB="ranlib -D"
		export AR="ar -D"

		make -j1

		unset SOURCE_DATE_EPOCH TZ LDFLAGS RANLIB AR
	fi

	mkdir -p "${SHVR_DIR_OUT}/bash_${version}/bin"
	cp bash "${SHVR_DIR_OUT}/bash_${version}/bin/bash"

	# Strip binary to ensure reproducible output
	strip --strip-all "${SHVR_DIR_OUT}/bash_${version}/bin/bash"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/bash_${version}/bin/bash"
	chmod 755 "${SHVR_DIR_OUT}/bash_${version}/bin/bash"

	"${SHVR_DIR_OUT}/bash_${version}/bin/bash" --version
}

shvr_deps_bash ()
{
	shvr_versioninfo_bash "$1"

	if test "$version_major" -lt 5 || { test "$version_major" -eq 5 && test "${version_minor}" -lt 3; }
	then apt-get -y install \
		curl patch gcc bison make ncurses-dev autoconf2.69 binutils
	else apt-get -y install \
		curl patch gcc bison make autoconf binutils
	fi
}
