#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# shvr_versions_from_html_listing <url> <regex_with_capture>
#
# Lists versions — with each entry's modification date — from an HTML directory
# listing (Apache/nginx autoindex, GNU mirrors, etc.) via `curl`. Autoindex
# pages place one file/dir per line with its date on the same line, so each line
# is processed independently: the line is tokenized on HTML delimiters and the
# anchored ERE (one capture group) is applied per token to extract the version,
# and the row's date column is read from the same line. This gives true
# capture-group support that a bare `grep -Eo` (whole-match only) cannot.
#
# The matching sed uses `#` as its s/// delimiter, so the regex may contain `/`
# (e.g. a trailing slash to match Apache directory entries like `0.37.0/`).
# Dates are accepted in both ISO (2006-10-24) and GNU month-name (2001-Apr-09)
# forms and normalized to ISO via shvr_iso_date.
#
# Output: one "<version> <YYYY-MM-DD>" per line, sorted descending by version
# (newest first). Returns 1 (and warns to stderr) on network failure or when
# zero tokens match, so callers can detect that discovery produced nothing.
shvr_versions_from_html_listing ()
(
	url="$1"
	regex="$2"

	# A unique temp dir per call: $$ is the (shared) main-shell PID even inside this
	# subshell function, so the previous "$$"-based paths collided when one call
	# nested inside another — e.g. shvr_update_bash streams the baseline listing
	# while calling this helper again per baseline to scrape its -patches/ dir. The
	# inner call clobbered the outer's temp files, so patch discovery returned empty
	# and every bash baseline composed to "<baseline>.0", freezing updates.
	base="$(mktemp -d "${TMPDIR:-/tmp}/shvr_html_listing.XXXXXX")"
	raw="${base}/raw"
	err="${base}/err"
	out="${base}/out"
	trap 'rm -rf "$base"' EXIT INT TERM

	# Fail fast on a host that blackholes us (e.g. one that blocks GitHub's runner
	# IP range) rather than hanging ~2min: a bounded connect-timeout, and only ONE
	# retry -- curl retries connect timeouts, so a large retry count would just
	# re-stack the timeout back toward the original hang. Worst case here is ~2
	# connect attempts (~40s), after which the caller (shvr_update) skips this
	# shell and keeps its committed versions; a transient blip is caught by the
	# single retry or by the next scheduled run.
	if ! curl -fsSL --connect-timeout 20 --retry 1 --retry-delay 3 "$url" > "$raw" 2> "$err"
	then
		echo "shvr_versions_from_html_listing: curl failed for ${url}" >&2
		sed 's/^/  /' "$err" >&2
		return 1
	fi

	while IFS= read -r line
	do
		version="$(printf '%s\n' "$line" | tr '"<>= ' '\n\n\n\n\n' | sed -nE "s#^${regex}\$#\\1#p" | head -n1)"
		test -n "$version" || continue
		date_raw="$(printf '%s\n' "$line" | grep -oE '[0-9]{4}-([0-9]{2}|[A-Za-z]{3})-[0-9]{2}' | head -n1)"
		if date_iso="$(shvr_iso_date "$date_raw" 2>/dev/null)" && test -n "$date_iso"
		then printf '%s %s\n' "$version" "$date_iso"
		else printf '%s\n' "$version"
		fi
	done < "$raw" | sort -V -u -r > "$out"

	if ! test -s "$out"
	then
		echo "shvr_versions_from_html_listing: no entries matched for ${url} (regex: ${regex})" >&2
		return 1
	fi

	cat "$out"
)
