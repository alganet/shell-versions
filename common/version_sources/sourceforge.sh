#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# shvr_versions_from_sourceforge <project> <path>
#
# Lists release versions — with each release's date — from a SourceForge
# project's file-feed RSS at
# https://sourceforge.net/projects/<project>/rss?path=<path>. Each <item> pairs
# a <title> file path like /zsh/5.9/zsh-5.9.tar.xz with a <pubDate>; versions
# are extracted from the tarball names following SourceForge's
# <project>-<version>.tar.* convention (the project name doubles as the tarball
# prefix), and dated from the item's RFC-822 <pubDate>. Signature/keyring
# entries (.asc) dedup to the same version or don't match. The <title> precedes
# the <pubDate> within each item, so they are paired by carrying the version
# forward to the next pubDate line.
#
# Output: one "<version> <YYYY-MM-DD>" per line, sorted descending by version
# (newest first). Returns 1 (and warns to stderr) on network failure or when
# zero titles match, so callers can detect that discovery produced nothing.
shvr_versions_from_sourceforge ()
(
	project="$1"
	path="$2"
	# Version token shape inside <project>-<version>.tar.*, as an awk ERE. Defaults
	# to the dotted-numeric stable form; callers scraping a pre-release path (e.g.
	# zsh's /zsh-test, whose tarballs are zsh-5.9.1.2-test.tar.xz) pass a wider one.
	verpat="${3:-[0-9.]+}"
	url="https://sourceforge.net/projects/${project}/rss?path=${path}"

	base="${TMPDIR:-/tmp}/shvr_sourceforge.$$"
	raw="${base}.raw"
	err="${base}.err"
	pairs="${base}.pairs"
	out="${base}.out"
	trap 'rm -f "$raw" "$err" "$pairs" "$out"' EXIT INT TERM

	if ! curl -fsSL "$url" > "$raw" 2> "$err"
	then
		echo "shvr_versions_from_sourceforge: curl failed for ${url}" >&2
		sed 's/^/  /' "$err" >&2
		return 1
	fi

	# Emit "<version>\t<RFC-822 pubDate>" per item: a <title> line sets the
	# pending version, the following <pubDate> line flushes it.
	awk -v proj="$project" -v verpat="$verpat" '
		/<title>/ {
			ver = ""
			if (match($0, proj "-" verpat "\\.tar\\.[gx]z")) {
				m = substr($0, RSTART, RLENGTH)
				sub("^" proj "-", "", m)
				sub("\\.tar\\..*$", "", m)
				ver = m
			}
		}
		/<pubDate>/ && ver != "" {
			d = $0
			sub(/.*<pubDate>/, "", d)
			sub(/<\/pubDate>.*/, "", d)
			print ver "\t" d
			ver = ""
		}
	' "$raw" > "$pairs"

	while IFS="$(printf '\t')" read -r version date_raw
	do
		test -n "$version" || continue
		if date_iso="$(shvr_iso_rfc822 "$date_raw" 2>/dev/null)" && test -n "$date_iso"
		then printf '%s %s\n' "$version" "$date_iso"
		else printf '%s\n' "$version"
		fi
	done < "$pairs" | sort -V -u -r > "$out"

	if ! test -s "$out"
	then
		echo "shvr_versions_from_sourceforge: no versions matched for ${url}" >&2
		return 1
	fi

	cat "$out"
)
