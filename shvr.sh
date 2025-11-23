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
		rm -Rf "${SHVR_DIR_SRC}/${interpreter}/$version"
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

# Helper: download a file and verify sha256 against checksums dir.
# Usage: shvr_fetch URL DEST
# Will derive checksum path from the DEST path relative to SHVR_DIR_SRC and
# will require a file at: ${SHVR_CHECKSUMS_DIR}/${rel}.sha256sums
shvr_fetch()
{
	url="$1"
	dest="$2"

	mkdir -p "$(dirname "$dest")"

	if ! test -f "$dest"
	then
		if command -v wget >/dev/null 2>&1
		then
			wget -q -O "$dest" "$url" || return 1
		elif command -v curl >/dev/null 2>&1
		then
			curl -sSL -o "$dest" "$url" || return 1
		else
			echo "neither wget nor curl available to download $url" >&2
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

	checksum_file="${SHVR_CHECKSUMS_DIR}/${relpath}.sha256sums"

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
		dest_dir="$(dirname "${SHVR_CHECKSUMS_DIR}/${rel}.sha256sums")"
		mkdir -p "$dest_dir"
		# write a file containing one line with: <sha256>  basename
		sha256sum "$f" | sed "s/  .*/  $(basename "$f")/" > "${SHVR_CHECKSUMS_DIR}/${rel}.sha256sums"
	done
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


shvr_github_regen_workflow ()
{
	local yml_file="${SHVR_DIR_SELF}/.github/workflows/$1.yml"
	set -- $(printf '%s ' $(shvr_${2:-targets} | sort -t'_' -k1,1 -k2Vr))
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
		echo "            targets: >"
		while test $# -gt 0
		do
			echo "              $1"
			shift
		done
	} > "$yml_file"
	rm "$yml_file.bak"
}

shvr_github_regen_all ()
{
	(shvr_github_regen_downloads)
	(shvr_github_regen_workflow docker-all targets)
	(shvr_github_regen_workflow docker-test targets)
	(shvr_github_regen_workflow docker-latest current)
}

shvr "${@:-}"