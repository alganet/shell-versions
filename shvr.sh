#!/usr/bin/env sh

# ISC License
#
# Copyright (c) 2023 Alexandre Gomes Gaigalas <alganet@gmail.com>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

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