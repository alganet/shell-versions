#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/ncurses.sh"

shvr_static_bash ()
{
	return 0
}

shvr_current_bash ()
{
	shvr_read_versions bash current
}

shvr_targets_bash ()
{
	shvr_read_versions bash all
}

shvr_update_bash ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/html_listing.sh"

	mirror="https://mirrors.ocf.berkeley.edu/gnu/bash/"

	# Discover baseline tarballs (bash-X.Y[a-z]?.tar.gz) with their dates. This
	# deliberately excludes three-component tarballs (bash-3.2.57.tar.gz),
	# release candidates (bash-4.0-rc1.tar.gz), and historical diffs/sigs — shvr
	# always builds from a baseline plus numbered patches, never the
	# pre-patched interim tarballs.
	shvr_versions_from_html_listing "$mirror" 'bash-([0-9]+\.[0-9]+[a-z]?)\.tar\.gz' |
		while IFS=' ' read -r baseline baseline_date
		do
			major="${baseline%%.*}"
			minor="${baseline#*.}"

			# A bash version is "<baseline>.<patch_count>", so scrape the
			# baseline's -patches/ dir for the highest bash<major><minor>-NNN
			# file (e.g. bash52-037, bash205b-013). The composed version's date
			# is the highest patch file's date; baselines with no patch dir 404
			# (stderr suppressed, expected) and compose to <baseline>.0 dated by
			# the baseline tarball.
			patch_line="$(shvr_versions_from_html_listing \
				"${mirror}bash-${baseline}-patches/" \
				"bash${major}${minor}-0*([0-9]+)" 2>/dev/null | head -n1)"

			# patch_line is "<patch> <date>" (or just "<patch>", leaving the
			# date empty).
			read -r patch patch_date <<EOF
${patch_line}
EOF

			if test -n "$patch"
			then printf '%s.%s %s\n' "$baseline" "$patch" "$patch_date"
			else printf '%s.0 %s\n' "$baseline" "$baseline_date"
			fi
		done |
		shvr_merge_versions bash
}

shvr_series_bash ()
{
	shvr_versioninfo_bash "$1" || return 1
	printf '%s\n' "${version_baseline}"
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

	shvr_download_ncurses
}

shvr_build_bash ()
{
	shvr_versioninfo_bash "$1"

	# Build static ncurses first
	shvr_build_ncurses

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

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC="$(shvr_musl_cc) -static"
	export AR="$(shvr_musl_ar)"
	export RANLIB="$(shvr_musl_ranlib)"
	export LDFLAGS="-Wl,--build-id=none $(shvr_ncurses_ldflags)"
	export CPPFLAGS="$(shvr_ncurses_cflags)"

	# Replace config.sub with a modern version that recognizes musl
	cp "$(automake --print-libdir)/config.sub" support/

	if test "$version_major" -lt 5 || { test "$version_major" -eq 5 && test "${version_minor}" -lt 3; }
	then
		rm configure
		# bash <=2.05 embeds its version into the maintainer-generated
		# configure via esyscmd(cat _distribution)/esyscmd(cat _patchlevel),
		# but those files are not shipped. Because we regenerate configure,
		# BASHVERS/BASHPATCH would be empty and support/mkversion.sh would bail
		# ("usage: ..."), so version.h is never made. Recreate the files. Gated
		# to 2.01..2.05: 2.05a+ dropped this mechanism and must stay byte-stable.
		case "$version_baseline" in
		2.0[1-5])
			printf '%s\n' "$version_baseline" > _distribution
			printf '%s\n' "$version_patch" > _patchlevel
			;;
		esac
		# bash renamed --with-bash-malloc in 2.04; 2.01..2.03 only know the old
		# --with-gnu-malloc name, so --without-bash-malloc is silently ignored
		# and bash's internal malloc (broken on modern musl: "xmalloc: cannot
		# allocate ...") gets linked. Disable it under the name each tree knows.
		malloc_flag=--without-bash-malloc
		case "$version_baseline" in
		2.0[1-3]) malloc_flag=--without-gnu-malloc ;;
		esac
		export CFLAGS="-std=gnu90 -frandom-seed=1 $(shvr_ncurses_cflags)"
		export CFLAGS_FOR_BUILD='-std=gnu90'
		export AUTOCONF='autoconf2.69'
		$AUTOCONF
		./configure \
			--host=x86_64-linux-musl \
			--prefix="${SHVR_DIR_OUT}/bash_${version}" \
			"$malloc_flag"
	else
		export CFLAGS="-frandom-seed=1 $(shvr_ncurses_cflags)"
		./configure \
			--host=x86_64-linux-musl \
			--prefix="${SHVR_DIR_OUT}/bash_${version}" \
			--without-bash-malloc
	fi

	make -j1

	unset SOURCE_DATE_EPOCH TZ CC AR RANLIB CFLAGS LDFLAGS CPPFLAGS CFLAGS_FOR_BUILD AUTOCONF

	mkdir -p "${SHVR_DIR_OUT}/bash_${version}/bin"
	cp bash "${SHVR_DIR_OUT}/bash_${version}/bin/bash"

	# Strip binary to ensure reproducible output
	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/bash_${version}/bin/bash"

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
		curl patch bison autoconf2.69 automake
	else apt-get -y install \
		curl patch bison automake
	fi
}
