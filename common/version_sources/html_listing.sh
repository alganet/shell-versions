#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# shvr_versions_from_html_listing <url> <regex_with_capture>
#
# Lists versions from an HTML directory listing (Apache/nginx autoindex, GNU
# mirrors, etc.) via `curl`. The page is tokenized on HTML delimiters so each
# href/filename lands on its own line, then an anchored ERE with one capture
# group is applied per token; the captured substring is what gets emitted. This
# mirrors how shvr_versions_from_github_tags matches one tag per line, and gives
# true capture-group support that a bare `grep -Eo` (whole-match only) cannot.
#
# Output: one version per line, sorted descending by version (newest first).
# Returns 1 (and warns to stderr) on network failure or when zero tokens match,
# so callers can detect that the discovery silently produced nothing.
shvr_versions_from_html_listing ()
(
	url="$1"
	regex="$2"

	base="${TMPDIR:-/tmp}/shvr_html_listing.$$"
	raw="${base}.raw"
	err="${base}.err"
	out="${base}.out"
	trap 'rm -f "$raw" "$err" "$out"' EXIT INT TERM

	if ! curl -fsSL "$url" > "$raw" 2> "$err"
	then
		echo "shvr_versions_from_html_listing: curl failed for ${url}" >&2
		sed 's/^/  /' "$err" >&2
		return 1
	fi

	tr '"<>= ' '\n\n\n\n\n' < "$raw" |
		sed -nE "s/^${regex}\$/\\1/p" |
		sort -V -u -r > "$out"

	if ! test -s "$out"
	then
		echo "shvr_versions_from_html_listing: no entries matched for ${url} (regex: ${regex})" >&2
		return 1
	fi

	cat "$out"
)
