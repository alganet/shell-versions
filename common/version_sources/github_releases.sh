#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# shvr_versions_from_github_tags <owner>/<repo> [tag_regex]
#
# Lists tags from a GitHub repository via `git ls-remote --tags --refs` to
# avoid the GitHub API rate limit. Tags are filtered by an optional ERE
# regex with one capture group; the captured substring is what gets emitted.
# Without a regex, the bare tag name is emitted.
#
# Output: one version per line, sorted descending by version (newest first).
# Returns 1 (and warns to stderr) on network failure or when zero tags match,
# so callers can detect that the discovery silently produced nothing.
shvr_versions_from_github_tags ()
(
	repo="$1"
	regex="${2:-}"

	base="${TMPDIR:-/tmp}/shvr_gh_tags.$$"
	raw="${base}.raw"
	err="${base}.err"
	out="${base}.out"
	trap 'rm -f "$raw" "$err" "$out"' EXIT INT TERM

	if ! git ls-remote --tags --refs "https://github.com/${repo}" > "$raw" 2> "$err"
	then
		echo "shvr_versions_from_github_tags: git ls-remote failed for ${repo}" >&2
		sed 's/^/  /' "$err" >&2
		return 1
	fi

	if test -n "$regex"
	then awk '{sub(/^refs\/tags\//, "", $2); print $2}' "$raw" | sed -nE "s/^${regex}\$/\\1/p" | sort -V -u -r > "$out"
	else awk '{sub(/^refs\/tags\//, "", $2); print $2}' "$raw" | sort -V -u -r > "$out"
	fi

	if ! test -s "$out"
	then
		echo "shvr_versions_from_github_tags: no tags matched for ${repo} (regex: ${regex:-<none>})" >&2
		return 1
	fi

	cat "$out"
)
