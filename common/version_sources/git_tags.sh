#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# shvr_versions_from_git_tags <repo_url> [tag_regex]
#
# Lists tags from an arbitrary git repository — with each tag's authoring date —
# via a blobless bare clone + `git for-each-ref`. Unlike
# shvr_versions_from_github_tags (which takes <owner>/<repo>), this takes a full
# clone URL, so it works for any host (kernel.org cgit, salsa.debian.org, etc.).
# Tags are filtered by an optional ERE regex with one capture group; the
# captured substring is the emitted version. Without a regex, the bare tag name
# is emitted. The matching sed uses `#` as its s/// delimiter, so the regex may
# contain `/` (e.g. salsa's `debian/0.14.5` tag prefix).
#
# Output: one "<version> <YYYY-MM-DD>" per line, sorted descending by version
# (newest first). Returns 1 (and warns to stderr) on network failure or when
# zero tags match, so callers can detect that discovery produced nothing.
shvr_versions_from_git_tags ()
(
	repo="$1"
	regex="${2:-}"

	base="${TMPDIR:-/tmp}/shvr_git_tags.$$"
	clone="${base}.git"
	raw="${base}.raw"
	err="${base}.err"
	out="${base}.out"
	trap 'rm -rf "$clone" "$raw" "$err" "$out"' EXIT INT TERM

	if ! git clone --bare --filter=blob:none --quiet "$repo" "$clone" 2> "$err"
	then
		echo "shvr_versions_from_git_tags: git clone failed for ${repo}" >&2
		sed 's/^/  /' "$err" >&2
		return 1
	fi

	# "<tag> <YYYY-MM-DD>" per tag.
	# refname:strip=2 drops exactly refs/tags/ (refname:short can keep a
	# "tags/" prefix when a branch shares the tag's name); the salsa posh tags
	# (debian/0.14.5) keep their internal slash, which the `#`-delimited sed
	# regex handles.
	if ! git --git-dir="$clone" for-each-ref \
		--format='%(refname:strip=2) %(creatordate:short)' refs/tags > "$raw" 2> "$err"
	then
		echo "shvr_versions_from_git_tags: for-each-ref failed for ${repo}" >&2
		sed 's/^/  /' "$err" >&2
		return 1
	fi

	# Apply the caller regex to the bare tag (same `^${regex}$` semantics as the
	# old ls-remote path), carrying the date column along untouched.
	while IFS=' ' read -r tag date
	do
		if test -n "$regex"
		then version="$(printf '%s\n' "$tag" | sed -nE "s#^${regex}\$#\\1#p")"
		else version="$tag"
		fi
		test -n "$version" || continue
		printf '%s %s\n' "$version" "$date"
	done < "$raw" | sort -V -u -r > "$out"

	if ! test -s "$out"
	then
		echo "shvr_versions_from_git_tags: no tags matched for ${repo} (regex: ${regex:-<none>})" >&2
		return 1
	fi

	cat "$out"
)
