#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# shvr_versions_from_sourceforge <project> <path>
#
# Lists release versions from a SourceForge project's file-feed RSS at
# https://sourceforge.net/projects/<project>/rss?path=<path>. Each <item> title
# is a file path like /zsh/5.9/zsh-5.9.tar.xz; versions are extracted from the
# tarball names following SourceForge's <project>-<version>.tar.* convention, so
# the project name doubles as the tarball prefix. Signature/keyring entries
# (.asc) dedup to the same version or don't match.
#
# Output: one version per line, sorted descending by version (newest first).
# Returns 1 (and warns to stderr) on network failure or when zero titles match,
# so callers can detect that the discovery silently produced nothing.
shvr_versions_from_sourceforge ()
(
	project="$1"
	path="$2"
	url="https://sourceforge.net/projects/${project}/rss?path=${path}"

	base="${TMPDIR:-/tmp}/shvr_sourceforge.$$"
	raw="${base}.raw"
	err="${base}.err"
	out="${base}.out"
	trap 'rm -f "$raw" "$err" "$out"' EXIT INT TERM

	if ! curl -fsSL "$url" > "$raw" 2> "$err"
	then
		echo "shvr_versions_from_sourceforge: curl failed for ${url}" >&2
		sed 's/^/  /' "$err" >&2
		return 1
	fi

	# `#` sed delimiter so the regex can match the `/`-bearing RSS title paths.
	grep '<title>' "$raw" |
		sed -nE "s#.*${project}-([0-9.]+)\.tar\.[gx]z.*#\\1#p" |
		sort -V -u -r > "$out"

	if ! test -s "$out"
	then
		echo "shvr_versions_from_sourceforge: no versions matched for ${url}" >&2
		return 1
	fi

	cat "$out"
)
