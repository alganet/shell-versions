#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/ncurses.sh"
. "${SHVR_DIR_SELF}/common/patches.sh"

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

	# Pre-releases sit beside the finals as bash-X.Y-{alpha,beta,rcN}.tar.gz, a
	# single self-contained tarball with no -patches/ dir. shvr_merge_prereleases
	# keeps only the newest one and writes versions/bash.prerelease, which feeds
	# :all (via shvr_targets_bash) but never :latest.
	shvr_versions_from_html_listing "$mirror" \
		'bash-([0-9]+\.[0-9]+-(alpha|beta|rc[0-9]*))\.tar\.gz' |
		shvr_merge_prereleases bash
}

# The branch the next bash accrues on. master carries the released tree and devel the
# development line -- at time of writing they report 5.3-release and 5.3-maint
# respectively, so devel is where 5.4 will appear, and tracking it means users get the
# next bash as soon as it begins to exist.
shvr_snapshotsource_bash ()
{
	echo "https://git.savannah.gnu.org/git/bash.git devel"
}

shvr_series_bash ()
{
	shvr_versioninfo_bash "$1" || return 1
	printf '%s\n' "${version_baseline}"
}

shvr_versioninfo_bash ()
{
	version="$1"

	# A development snapshot (snapshot-<shortsha>). This must come before the numeric
	# parsing below, which would reject the token outright: it contains no ".", so
	# version_major would equal version and we would return 1.
	#
	# The gates in build/deps all ask "is this new enough for the modern behaviour", so
	# an effectively-infinite version uniformly selects the newest code path -- which is
	# exactly what a snapshot is. It also keeps bash off the <5.3 path, which does
	# `rm configure; autoconf2.69`: the devel tree ships a good generated configure but
	# NOT _distribution/_patchlevel, which configure.ac reads via esyscmd(), so
	# regenerating would bake in an empty version (the failure that
	# patches/bash/distribution-*.diff exists to fix for 2.01..2.05).
	if shvr_is_snapshot "$version"
	then
		version_major=99
		version_minor=99
		version_patch=0
		version_baseline="$version"
		build_srcdir="${SHVR_DIR_SRC}/bash/${version}"
		return 0
	fi

	version_major="${version%%\.*}"

	if test "$version" = "$version_major"
	then return 1
	fi

	# A pre-release (5.3-rc2) is a standalone baseline tarball with zero numbered
	# patches: the whole token is the baseline. Derive a numeric minor from the
	# base (5.3-rc2 -> 3) so the configure-path gating below still keys off the
	# real major.minor, and point build_srcdir at the token's own tree.
	if shvr_is_prerelease "$version"
	then
		version_baseline="$version"
		version_patch=0
		version_minor="${version%%-*}"
		version_minor="${version_minor#*.}"
		build_srcdir="${SHVR_DIR_SRC}/bash/${version_baseline}"
		return 0
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

	# A snapshot has no tarball to fetch: savannah serves no cgit snapshots (its
	# /snapshot/ URLs answer 400) and there is no mirror to fall back on. So fetch the
	# tree by its pinned sha -- shallow, so it costs one commit rather than bash's whole
	# history -- and archive it into the tarball the build already knows how to unpack,
	# leaving shvr_build_bash untouched.
	#
	# This is the one lane with no committed SOURCE checksum: shvr_fetch is bypassed and
	# the sha is the pin, which is a stronger one than a sha256 of a tarball we minted
	# ourselves. The archive's bytes need not be reproducible -- nothing checksums them
	# -- while the BUILD checksums still are, because they are taken over the compiled
	# binary, which depends on the tree the sha names, not on the tarball's framing.
	if shvr_is_snapshot "$version"
	then
		if ! test -f "${build_srcdir}.tar.gz"
		then
			bash_sn_sha="$(shvr_snapshot_sha bash "$version")"
			bash_sn_repo="$(shvr_snapshotsource_bash | cut -d' ' -f1)"
			bash_sn_tmp="$(mktemp -d "${TMPDIR:-/tmp}/shvr_bash_snapshot.XXXXXX")"

			git init -q "$bash_sn_tmp"
			git -C "$bash_sn_tmp" remote add origin "$bash_sn_repo"
			git -C "$bash_sn_tmp" fetch -q --depth 1 origin "$bash_sn_sha"
			# Write via a temp so an interrupted fetch cannot leave a partial tarball
			# to be cached and unpacked.
			git -C "$bash_sn_tmp" archive --format=tar.gz \
				--prefix="bash-${version}/" FETCH_HEAD > "${build_srcdir}.tar.gz.part"
			mv "${build_srcdir}.tar.gz.part" "${build_srcdir}.tar.gz"
			rm -rf "$bash_sn_tmp"
		fi

		shvr_download_ncurses
		return 0
	fi

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

	# Start from a clean tree. build_srcdir is keyed on the BASELINE, but
	# shvr_each cleans up ${SHVR_DIR_SRC}/bash/${version} -- a path that never
	# exists -- so the extraction survives between local runs. Untarring over it
	# restores everything the tarball carries, but not files we add ourselves:
	# distribution-*.diff creates _distribution and _patchlevel, and a second run
	# would find them already there and abort with "previously applied patch".
	# CI is unaffected (fresh container), but a local rebuild must not be.
	rm -Rf "${build_srcdir}"
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

	# Ours, as opposed to the upstream GNU patches applied just above. Must land
	# before the configure regeneration below: distribution-*.diff restores the
	# two files configure.in reads through esyscmd().
	shvr_apply_patches bash "$version"

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CC="$(shvr_musl_cc) -static"
	export AR="$(shvr_musl_ar)"
	export RANLIB="$(shvr_musl_ranlib)"
	export LDFLAGS="-Wl,--build-id=none $(shvr_ncurses_ldflags)"
	export CPPFLAGS="$(shvr_ncurses_cflags)"

	# Replace config.sub/config.guess with modern versions that recognize musl
	# and non-x86 build machines. The bundled config.guess in older bash trees
	# predates aarch64 and aborts configure with "cannot guess build type" on an
	# arm64 build host; the modern one recognizes both. amd64 output is
	# unaffected (bash's MACHTYPE comes from --host, not the build triple).
	cp "$(automake --print-libdir)/config.sub" support/
	cp "$(automake --print-libdir)/config.guess" support/

	if test "$version_major" -lt 5 || { test "$version_major" -eq 5 && test "${version_minor}" -lt 3; }
	then
		rm configure
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
			--host="$(shvr_musl_target)" \
			--prefix="${SHVR_DIR_OUT}/bash_${version}" \
			"$malloc_flag"
	else
		export CFLAGS="-frandom-seed=1 $(shvr_ncurses_cflags)"
		./configure \
			--host="$(shvr_musl_target)" \
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
