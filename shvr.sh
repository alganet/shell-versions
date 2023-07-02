#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

set -euf

SHVR_DIR_SELF="$(cd "$(dirname "$0")"; pwd)"
SHVR_DIR_SRC="${SHVR_DIR_SRC:-"/usr/src/shvr"}"
SHVR_DIR_OUT="${SHVR_DIR_OUT:-"/opt"}"

shvr ()
{
	shvr_"${@:-}"
}

shvr_build ()
{
	set -x

	while test $# -gt 0
	do
		interpreter="${1%%_*}"
		version="${1#*_}"

		. "${SHVR_DIR_SELF}/variants/${interpreter}.sh"

		"shvr_build_${interpreter}" "$version"
		rm -Rf "${SHVR_DIR_SRC}/${interpreter}"
		shift
	done
}

shvr "${@:-}"