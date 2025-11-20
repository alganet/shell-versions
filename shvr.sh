#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

set -euf

SHVR_DIR_SELF="$(cd "$(dirname "$0")"; pwd)"
SHVR_DIR_SRC="${SHVR_DIR_SRC:-"${SHVR_DIR_SELF}/build"}"
SHVR_DIR_OUT="${SHVR_DIR_OUT:-"${SHVR_DIR_SELF}/out"}"

shvr ()
{
	mkdir -p "${SHVR_DIR_SRC}"
	mkdir -p "${SHVR_DIR_OUT}"
	shvr_"${@:-}"
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