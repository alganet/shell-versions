#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"

shvr_static_mksh ()
{
	return 0
}

shvr_current_mksh ()
{
	shvr_read_versions mksh current
}

shvr_targets_mksh ()
{
	shvr_read_versions mksh all
}

shvr_update_mksh ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/github_releases.sh"
	shvr_versions_from_github_tags MirBSD/mksh 'mksh-(R[0-9]+[a-z]?)' |
		shvr_merge_versions mksh
}

shvr_series_mksh ()
{
	shvr_versioninfo_mksh "$1" || return 1
	printf 'R%s\n' "${version_major}"
}

shvr_versioninfo_mksh ()
{
	version="$1"
	rest="${version#R}"
	if test "$rest" = "$version"
	then return 1
	fi
	version_major="${rest%%[!0-9]*}"
	if test -z "$version_major"
	then return 1
	fi
	version_patch="${rest#$version_major}"
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

	if test -d "${SHVR_DIR_SELF}/patches/mksh/$version"
	then
		find "${SHVR_DIR_SELF}/patches/mksh/$version" -type f -o -type l | sort | while read -r patch_file
		do patch -p0 < "$patch_file"
		done
	fi

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC="$(shvr_musl_cc) -static"
	export AR="$(shvr_musl_ar)"
	export RANLIB="$(shvr_musl_ranlib)"
	export CFLAGS="-frandom-seed=1"
	export LDFLAGS="-Wl,--build-id=none"

	# <R30 generates its signal-name table by preprocessing a synthetic source
	# and parsing the expanded numbers (the "Generating list of signal names"
	# step, and the NSIG probe before it). The cross gcc's default `-E` emits
	# `# line` markers around every macro expansion, so `NSIG`/`SIGxxx` land on
	# their own lines split from the surrounding text; Build.sh then reads NSIG=0
	# and aborts with `exit 1`. Forcing the preprocessor to `-E -P` (no line
	# markers) keeps each expansion inline. Build.sh honours a pre-set $CPP, so
	# export it for the affected band; R30+ extract signals without this.
	if test "$version_major" -lt 30
	then export CPP="$(shvr_musl_cc) -static -E -P -"
	fi

	sh ./Build.sh

	unset SOURCE_DATE_EPOCH TZ CC AR RANLIB CFLAGS LDFLAGS CPP

	mkdir -p "${SHVR_DIR_OUT}/mksh_${version}/bin"
	cp "mksh" "${SHVR_DIR_OUT}/mksh_$version/bin"

	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/mksh_${version}/bin/mksh"
	touch -d "@1" "${SHVR_DIR_OUT}/mksh_${version}/bin/mksh"
	chmod 755 "${SHVR_DIR_OUT}/mksh_${version}/bin/mksh"

	"${SHVR_DIR_OUT}/mksh_${version}/bin/mksh" -c "echo mksh version $version"
}

shvr_deps_mksh ()
{
	:
}
