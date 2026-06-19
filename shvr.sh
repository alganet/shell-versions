#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

set -euf

SHVR_DIR_SELF="$(cd "$(dirname "$0")"; pwd)"
SHVR_DIR_SRC="${SHVR_DIR_SRC:-"${SHVR_DIR_SELF}/build"}"
SHVR_DIR_OUT="${SHVR_DIR_OUT:-"${SHVR_DIR_SELF}/out"}"
SHVR_CHECKSUMS_DIR="${SHVR_CHECKSUMS_DIR:-"${SHVR_DIR_SELF}/checksums"}"
# Default: verify by default; set SHVR_SKIP_VERIFY_SHA256=1 to disable verification
SHVR_SKIP_VERIFY_SHA256="${SHVR_SKIP_VERIFY_SHA256:-0}"

shvr ()
{
	mkdir -p "${SHVR_DIR_SRC}"
	mkdir -p "${SHVR_DIR_OUT}"
	# Allow hyphen or underscore in command names: normalize to underscore
	cmd="$1"
	shift || true
	cmd="$(echo "$cmd" | sed 's/-/_/g')"
	shvr_${cmd} "${@:-}"
}

shvr_build ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_targets))
	fi

	set -x

	shvr_each build "${@:-}"
	shvr_generate_build_checksums "${@:-}"
}


shvr_deps ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_targets))
	fi

	set -x

	shvr_each deps "${@:-}"
}

shvr_download ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_targets))
	fi

	set -x

	shvr_each download "${@:-}"
}

shvr_targets ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_interpreters))
	fi

	shvr_each targets "${@:-}"
}

shvr_current ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_interpreters))
	fi

	shvr_each current "${@:-}"
}

shvr_update ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_interpreters))
	fi

	while test $# -gt 0
	do
		interpreter="$1"
		. "${SHVR_DIR_SELF}/variants/${interpreter}.sh"
		if command -v "shvr_update_${interpreter}" >/dev/null 2>&1
		then "shvr_update_${interpreter}"
		else echo "skip: ${interpreter} has no updater yet" >&2
		fi
		shift
	done
}

shvr_interpreters ()
{
	find "${SHVR_DIR_SELF}/variants" -type f |
		while read -r variant_file
		do basename "${variant_file}" | sed 's/\.sh$//'
		done |
		sort
}

shvr_each ()
{
	subcommand="$1"
	shift

	while test $# -gt 0
	do
		build_srcdir=""
		interpreter="${1%%_*}"
		version="${1#*_}"

		. "${SHVR_DIR_SELF}/variants/${interpreter}.sh"

		"shvr_${subcommand}_${interpreter}" "$version"
		# Allow keeping the extracted build tree for debugging when
		# SHVR_KEEP_BUILD=1. Otherwise clean it after each individual build.
		if test $subcommand = "build" && test "${SHVR_KEEP_BUILD:-0}" != "1"
		then
			rm -Rf "${SHVR_DIR_SRC}/${interpreter}/$version"
		fi
		shift
	done
}

shvr_clear_versioninfo ()
{
	version=""
	version_major=""
	version_minor=""
	version_patch=""
	version_baseline=""
	fork_name=""
	fork_version=""
	build_srcdir=""
}

shvr_untar()
{
	tar --extract \
		--file="$1" \
		--strip-components=1 \
		--directory="$2" \
		--owner=0 \
		--group=0 \
		--mode=go-w
}

shvr_read_versions ()
{
	interpreter="$1"
	which="$2"
	file="${SHVR_DIR_SELF}/versions/${interpreter}.${which}"
	# versions/<shell>.all carries a "<version> <date>" second column; strip it
	# so build/target ids stay <shell>_<version>. Harmless on the version-only
	# .current / .excluded files (no whitespace to strip).
	if test -f "$file"
	then sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' -e 's/[[:space:]].*$//' -e "s/^/${interpreter}_/" "$file"
	fi
}

shvr_filter_latest_per_series ()
{
	keyfn="$1"
	while IFS= read -r ver
	do
		if key="$("$keyfn" "$ver" 2>/dev/null)" && test -n "$key"
		then printf '%s\t%s\n' "$key" "$ver"
		fi
	done |
		sort -V -r |
		awk -F '\t' '!seen[$1]++ { print $2 }'
}

shvr_filter_excluded ()
{
	excluded_file="$1"
	if test -s "$excluded_file"
	then grep -v -F -x -f "$excluded_file"
	else cat
	fi
}

shvr_merge_versions ()
{
	interpreter="$1"
	file="${SHVR_DIR_SELF}/versions/${interpreter}.all"
	mkdir -p "$(dirname "$file")"

	if ! test -f "$file"
	then : > "$file"
	fi

	excluded_file="${SHVR_DIR_SELF}/versions/${interpreter}.excluded"

	# Subshell so the EXIT trap is function-scoped (POSIX traps are
	# process-scoped otherwise).
	(
		tmp="${file}.tmp.$$"
		discovered="${tmp}.discovered"
		existing="${tmp}.existing"
		excluded="${tmp}.excluded"
		versions="${tmp}.versions"
		datemap="${tmp}.datemap"
		merged="${tmp}.merged"
		existing_v="${tmp}.existing_v"
		new_only="${tmp}.new"
		dropped="${tmp}.dropped"

		trap 'rm -f "$discovered" "$existing" "$excluded" "$versions" "$datemap" "$merged" "$existing_v" "$new_only" "$dropped"' EXIT INT TERM

		cat > "$discovered"

		if ! test -s "$discovered"
		then
			echo "${interpreter}: no versions discovered (upstream fetch may have failed); refusing to overwrite ${file}" >&2
			exit 1
		fi

		sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' "$file" > "$existing"

		if test -f "$excluded_file"
		then sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' "$excluded_file" > "$excluded"
		else : > "$excluded"
		fi

		if command -v "shvr_series_${interpreter}" >/dev/null 2>&1
		then series_filter="shvr_filter_latest_per_series shvr_series_${interpreter}"
		else series_filter="cat"
		fi

		# Lines (existing and discovered) are "<version>" or "<version> <date>".
		# Work the set math on the bare version column so the exclude/series
		# filters stay date-agnostic, then re-attach dates from a version->date
		# map that prefers the committed (existing) date over the discovered one.

		# Union existing + discovered versions, drop excluded, dedupe to one
		# entry per series, sort descending by version.
		cat "$existing" "$discovered" |
			awk '{print $1}' |
			shvr_filter_excluded "$excluded" |
			$series_filter |
			sort -V -u -r > "$versions"

		# version->date map: existing dates win, discovered fills the gaps.
		cat "$existing" "$discovered" |
			awk 'NF >= 2 && !($1 in d) { d[$1] = $2; print $1, $2 }' > "$datemap"

		# Re-attach dates, preserving the version sort order.
		awk 'NR == FNR { d[$1] = $2; next }
			{ if ($1 in d) print $1, d[$1]; else print $1 }' \
			"$datemap" "$versions" > "$merged"

		# $versions is already the bare, sorted version column of $merged.
		awk '{print $1}' "$existing" > "$existing_v"

		if test -s "$existing_v"
		then grep -v -F -x -f "$existing_v" "$versions" > "$new_only" || true
		else cp "$versions" "$new_only"
		fi

		if test -s "$existing_v"
		then grep -v -F -x -f "$versions" "$existing_v" > "$dropped" || true
		else : > "$dropped"
		fi

		cp "$merged" "$file"

		if test -s "$new_only"
		then
			n_new=$(wc -l < "$new_only" | tr -d ' ')
			echo "${interpreter}: added ${n_new} new version(s):" >&2
			sed 's/^/  /' "$new_only" >&2
		fi

		if test -s "$dropped"
		then
			n_drop=$(wc -l < "$dropped" | tr -d ' ')
			echo "${interpreter}: dropped ${n_drop} version(s):" >&2
			sed 's/^/  /' "$dropped" >&2
		fi

		if ! test -s "$new_only" && ! test -s "$dropped"
		then echo "${interpreter}: no changes" >&2
		fi
	)
}

# Map an English month name to a zero-padded number, case-insensitively (the
# date sources emit title-case names like Sep/May).
shvr_month_num ()
{
	case "$1" in
	Jan|jan|JAN) printf '01' ;;
	Feb|feb|FEB) printf '02' ;;
	Mar|mar|MAR) printf '03' ;;
	Apr|apr|APR) printf '04' ;;
	May|may|MAY) printf '05' ;;
	Jun|jun|JUN) printf '06' ;;
	Jul|jul|JUL) printf '07' ;;
	Aug|aug|AUG) printf '08' ;;
	Sep|sep|SEP) printf '09' ;;
	Oct|oct|OCT) printf '10' ;;
	Nov|nov|NOV) printf '11' ;;
	Dec|dec|DEC) printf '12' ;;
	*) return 1 ;;
	esac
}

# Normalize a directory-listing date token to ISO YYYY-MM-DD. Accepts the ISO
# form (2022-09-26, passed through) and the GNU autoindex month-name form
# (2022-Sep-26). Returns 1 on anything else so callers can drop the date.
shvr_iso_date ()
{
	case "$1" in
	[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
		printf '%s' "$1"
		;;
	[0-9][0-9][0-9][0-9]-[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9])
		_y="${1%%-*}"
		_rest="${1#*-}"
		_mon="${_rest%%-*}"
		_day="${_rest##*-}"
		_m="$(shvr_month_num "$_mon")" || return 1
		printf '%s-%s-%s' "$_y" "$_m" "$_day"
		;;
	*) return 1 ;;
	esac
}

# Convert an RFC-822 date (RSS <pubDate>, e.g. "Sun, 31 May 2026 20:55:59 UT")
# to ISO YYYY-MM-DD. Subshell so `set --` does not clobber caller positionals.
shvr_iso_rfc822 ()
(
	# shellcheck disable=SC2086
	set -- $1
	# $1=weekday, $2=day, $3=month, $4=year
	_day="${2#0}"
	_m="$(shvr_month_num "$3")" || return 1
	printf '%s-%s-%02d' "$4" "$_m" "$_day"
)

# Print the recorded ISO date for <interpreter> <version>, or nothing if the
# version is absent or undated in versions/<interpreter>.all. Interpreters with
# no .all of their own (ash, hush reuse busybox) may declare a backing shell via
# a shvr_versionsource_<interpreter> hook in their variant; the variant is
# loaded on demand so this works even outside the per-shell dispatch.
shvr_version_date ()
{
	interpreter="$1"
	version="$2"
	if ! test -f "${SHVR_DIR_SELF}/versions/${interpreter}.all"
	then
		vf="${SHVR_DIR_SELF}/variants/${interpreter}.sh"
		if ! command -v "shvr_versionsource_${interpreter}" >/dev/null 2>&1 && test -f "$vf"
		then . "$vf"
		fi
		if command -v "shvr_versionsource_${interpreter}" >/dev/null 2>&1
		then interpreter="$("shvr_versionsource_${interpreter}")"
		fi
	fi
	file="${SHVR_DIR_SELF}/versions/${interpreter}.all"
	if test -f "$file"
	then awk -v v="$version" '$1 == v && NF >= 2 { print $2; exit }' "$file"
	fi
}

# Filter <shell>_<version> target ids on stdin to those released on or after
# SHVR_SINCE (ISO YYYY-MM-DD). With SHVR_SINCE unset, passes everything through.
# Undated targets are dropped with a warning rather than crashing.
shvr_filter_since ()
{
	since="${SHVR_SINCE:-}"
	if test -z "$since"
	then cat; return 0
	fi
	while IFS= read -r target
	do
		test -n "$target" || continue
		interpreter="${target%%_*}"
		version="${target#*_}"
		printf '%s\t%s\n' "$target" "$(shvr_version_date "$interpreter" "$version")"
	done |
		awk -F '\t' -v s="$since" '
			$2 == "" { print "shvr_filter_since: " $1 " has no date; dropping" > "/dev/stderr"; next }
			$2 >= s { print $1 }'
}

shvr_fetch()
{
	url="$1"
	dest="$2"

	mkdir -p "$(dirname "$dest")"

	if ! test -f "$dest"
	then
		if command -v curl >/dev/null 2>&1
		then
			curl -sSL -o "$dest" "$url" || return 1
		else
			echo "curl is required to download $url" >&2
			return 1
		fi
	fi

	if test "${SHVR_SKIP_VERIFY_SHA256}" = "1"
	then
		# skip verification when explicitly requested
		return 0
	fi

	# Only verify files under SHVR_DIR_SRC; for others derive from absolute
	# path by stripping leading slash and using that relative path in checksums.
	case "$dest" in
		${SHVR_DIR_SRC}/*)
			relpath="${dest#${SHVR_DIR_SRC}/}"
			;;
		/*)
			relpath="${dest#/}"
			;;
		*)
			relpath="$dest"
			;;
	esac

	checksum_file="${SHVR_CHECKSUMS_DIR}/sources/${relpath}.sha256sums"

	if ! test -f "$checksum_file"
	then
		echo "checksum missing for $dest, expected at $checksum_file" >&2
		return 1
	fi

	# Run verification: change to dest dir so relative filenames match
	savedir="$(pwd)"
	cd "$(dirname "$dest")"
	if ! sha256sum -c "$checksum_file" >/dev/null 2>&1
	then
		echo "sha256sum mismatch for $dest (checksum file: $checksum_file)" >&2
		cd "$savedir"
		return 1
	fi
	cd "$savedir"
	return 0
}

shvr_generate_checksums()
{

	start_dir="${SHVR_DIR_SRC}"

	find "$start_dir" -type f | while read -r f
	do
		rel="${f#${SHVR_DIR_SRC}/}"
		dest_dir="$(dirname "${SHVR_CHECKSUMS_DIR}/sources/${rel}.sha256sums")"
		mkdir -p "$dest_dir"
		# write a file containing one line with: <sha256>  basename
		sha256sum "$f" | sed "s/  .*/  $(basename "$f")/" > "${SHVR_CHECKSUMS_DIR}/sources/${rel}.sha256sums"
	done
}


# Generate checksums for build outputs under ${SHVR_DIR_OUT} and write them
# to ${SHVR_CHECKSUMS_DIR}/build/<rel>.sha256sums mirroring the out layout.
# Usage: shvr_generate_build_checksums [<shell>_<version> ...]
shvr_generate_build_checksums()
{
	if test -z "$*"
	then
		start_dir="${SHVR_DIR_OUT}"
		find "$start_dir" -type f -not -path '*/shvr/*' | while read -r f
		do
			rel="${f#${SHVR_DIR_OUT}/}"
			dest_dir="$(dirname "${SHVR_CHECKSUMS_DIR}/build/${rel}.sha256sums")"
			mkdir -p "$dest_dir"
			sha256sum "$f" | sed "s/  .*/  $(basename "$f")/" > "${SHVR_CHECKSUMS_DIR}/build/${rel}.sha256sums"
		done
	else
		# Only generate checksums for specific targets (e.g., bash_5.3.9)
		for t in "$@"
		do
			dir="$SHVR_DIR_OUT/${t}"
			if test -d "$dir"
			then
				find "$dir" -type f | while read -r f
				do
					rel="${f#${SHVR_DIR_OUT}/}"
					dest_dir="$(dirname "${SHVR_CHECKSUMS_DIR}/build/${rel}.sha256sums")"
					mkdir -p "$dest_dir"
					sha256sum "$f" | sed "s/  .*/  $(basename "$f")/" > "${SHVR_CHECKSUMS_DIR}/build/${rel}.sha256sums"
				done
			fi
		done
	fi
}

# Verify build outputs against committed checksums in ${SHVR_CHECKSUMS_DIR}/build/.
# Reports all failures before exiting so CI logs show every mismatch.
# Usage: shvr_verify_build_checksums [<shell>_<version> ...]
shvr_verify_build_checksums()
{
	if test "${SHVR_SKIP_VERIFY_SHA256}" = "1"
	then
		return 0
	fi

	checksums_dir="${SHVR_CHECKSUMS_DIR}/build"

	if ! test -d "$checksums_dir"
	then
		echo "no build checksums directory at $checksums_dir" >&2
		return 1
	fi

	fail_count=0

	if test -z "$*"
	then
		search_dir="$checksums_dir"
	else
		search_dir=""
		for t in "$@"
		do
			target_dir="${checksums_dir}/${t}"
			if ! test -d "$target_dir"
			then
				echo "no build checksums for target $t at $target_dir" >&2
				fail_count=$((fail_count + 1))
				continue
			fi
			search_dir="${search_dir} ${target_dir}"
		done
	fi

	for d in $search_dir
	do
		for checksum_file in $(find "$d" -name '*.sha256sums')
		do
			rel="${checksum_file#${checksums_dir}/}"
			# Strip .sha256sums suffix to get the relative path of the binary
			bin_rel="${rel%.sha256sums}"
			bin_path="${SHVR_DIR_OUT}/${bin_rel}"

			if ! test -f "$bin_path"
			then
				echo "FAIL missing binary: $bin_path (expected by $checksum_file)" >&2
				fail_count=$((fail_count + 1))
				continue
			fi

			savedir="$(pwd)"
			cd "$(dirname "$bin_path")"
			if ! sha256sum -c "$checksum_file" >/dev/null 2>&1
			then
				expected=$(cat "$checksum_file")
				actual=$(sha256sum "$(basename "$bin_path")" | sed "s/  .*/  $(basename "$bin_path")/")
				echo "FAIL $bin_rel" >&2
				echo "  expected: $expected" >&2
				echo "  actual:   $actual" >&2
				fail_count=$((fail_count + 1))
			fi
			cd "$savedir"
		done
	done

	if test "$fail_count" -gt 0
	then
		echo "build checksum verification failed: $fail_count error(s)" >&2
		return 1
	fi
}

shvr_github_regen_downloads ()
{
	set -- $(printf '%s ' $(shvr_targets | sort -t'_' -k1,1 -k2Vr))
	local yml_file="${SHVR_DIR_SELF}/.github/actions/downloads/action.yml"
	cp -f "$yml_file" "${yml_file}.bak"
	IFS=
	cat "$yml_file.bak" |
	{
		while read -r yml_line
		do
			echo "${yml_line}"
			case ${yml_line} in
				*'# AUTO-GENERATED LIST. DO NOT EDIT MANUALLY.'*)
					break
					;;
			esac
		done
		echo "  steps:"
		while test $# -gt 0
		do
			shvr_clear_versioninfo
			interpreter="${1%%_*}"
			version="${1#*_}"
			. "${SHVR_DIR_SELF}/variants/${interpreter}.sh"
			shvr_versioninfo_"${interpreter}" "$version"

			cat <<-@ | sed 's/.//'
				|    - uses: ./.github/actions/single-download
				|      with:
				|        shvr_shell: $interpreter
				|        shvr_version: "$version"
				|        cache_path: "${build_srcdir#${SHVR_DIR_SRC}/}"
			@

			shift
		done
	 } > "$yml_file"
	 rm "$yml_file.bak"
}


shvr_github_regen_docker_workflow ()
{
	local yml_file="${SHVR_DIR_SELF}/.github/workflows/docker.yml"
	local all_targets="$(printf '%s ' $(shvr_targets | sort -t'_' -k1,1 -k2Vr))"
	local current_targets="$(printf '%s ' $(shvr_current | sort -t'_' -k1,1 -k2Vr))"
	cp -f "$yml_file" "${yml_file}.bak"
	cat "$yml_file.bak" |
	{
		# Read until matrix marker (inclusive)
		while IFS= read -r yml_line
		do
			echo "${yml_line}"
			case ${yml_line} in
				*'# AUTO-GENERATED MATRIX. DO NOT EDIT MANUALLY.'*)
					break
					;;
			esac
		done
		# Emit all targets as matrix entries
		for target in $all_targets
		do
			shvr_clear_versioninfo
			interpreter="${target%%_*}"
			version="${target#*_}"
			. "${SHVR_DIR_SELF}/variants/${interpreter}.sh"
			shvr_versioninfo_"${interpreter}" "$version"
			cat <<-@ | sed 's/.//'
			|          - target: $target
			|            shell: $interpreter
			|            version: "$version"
			|            cache_path: "${build_srcdir#${SHVR_DIR_SRC}/}"
			@
		done
		# Skip old build matrix entries until assemble job boundary
		while IFS= read -r yml_line
		do
			case ${yml_line} in
				'  assemble:'*)
					break
					;;
			esac
		done
		# Echo static assemble job header until assemblies marker
		echo ""
		echo "${yml_line}"
		while IFS= read -r yml_line
		do
			echo "${yml_line}"
			case ${yml_line} in
				*'# AUTO-GENERATED ASSEMBLIES. DO NOT EDIT MANUALLY.'*)
					break
					;;
			esac
		done
		# Emit assembly matrix entries
		echo "          - flavor: latest"
		echo "            targets: >"
		for target in $current_targets
		do
			echo "              $target"
		done
		echo "          - flavor: all"
		echo "            targets: >"
		for target in $all_targets
		do
			echo "              $target"
		done
		# Skip old assembly entries until steps:
		while IFS= read -r yml_line
		do
			case ${yml_line} in
				'    steps:'*)
					break
					;;
			esac
		done
		# Echo steps and remaining content
		echo "${yml_line}"
		while IFS= read -r yml_line
		do
			echo "${yml_line}"
		done
	} > "$yml_file"
	rm "$yml_file.bak"
}

shvr_toolchain_download ()
{
	. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
	. "${SHVR_DIR_SELF}/common/rustup.sh"
	shvr_download_musl_cross_make
	shvr_download_rustup
}

shvr_musl_build ()
{
	. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
	apt-get -y install gcc g++ make curl patch xz-utils
	shvr_download_musl_cross_make
	shvr_build_musl_cross_make
}

shvr_github_regen_all ()
{
	(shvr_github_regen_downloads)
	(shvr_github_regen_docker_workflow)
}

shvr "${@:-}"