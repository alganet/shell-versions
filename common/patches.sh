#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# Source patching, quilt style. Each patch set lives in a flat directory
# patches/<set>/ holding .diff files and one `series` file that says which
# versions each .diff applies to:
#
#	# <patch-file>  <version> [<version> ...]
#	arith-c-include-wctype.diff  2.10 2.11 2.12
#	common-h-has-builtin-guard.diff  2.61
#
# Patches are applied with `patch -p0` from the extracted source root, in the
# order the series file lists them. Selectors are ordinary shell globs matched
# against the exact version token, so `1.0.*-uplusm` works -- but prefer
# explicit token lists, which can be audited line by line against
# versions/<shell>.all. Every version band in this repo is closed and
# historical, so there is deliberately no version comparator here: a range
# expression that silently widened would patch a version that must stay
# byte-identical to its committed build checksum.
#
# A variant that patches must source this file with a literal
# ${SHVR_DIR_SELF}/common/patches.sh path. That is not style: shvr_recipe_files
# greps the variant for such literals to build the target's OID, and a helper
# reached only indirectly would not be folded into the build identity.

# The patch set a shell draws from. Normally the shell's own name; ash and hush
# share one busybox source tree (build_srcdir=${SHVR_DIR_SRC}/busybox/<version>)
# and therefore one patch set, keyed by the source rather than by the applet.
shvr_patchset ()
{
	case "$1" in
	ash|hush) printf 'busybox\n' ;;
	*)        printf '%s\n' "$1" ;;
	esac
}

# Print the patch files selected for <version> of patch set <set>, one per line,
# in series order. Prints nothing (successfully) if the set has no series file.
shvr_patch_list ()
{
	sp_dir="${SHVR_DIR_SELF}/patches/$1"
	sp_version="$2"

	if ! test -f "${sp_dir}/series"
	then return 0
	fi

	# Join backslash-continued lines so a long selector list can wrap.
	sed -e ':x' -e '/\\$/{N;s/\\\n//;bx' -e '}' "${sp_dir}/series" |
		while IFS= read -r sp_line
		do
			case "$sp_line" in
			''|'#'*) continue ;;
			esac

			# Deliberate word splitting: <file> then the selectors.
			# shellcheck disable=SC2086
			set -- $sp_line
			sp_file="$1"
			shift

			for sp_pat in "$@"
			do
				# Glob match against the exact version token.
				case "$sp_version" in
				$sp_pat)
					printf '%s/%s\n' "${sp_dir}" "${sp_file}"
					break
					;;
				esac
			done
		done
}

# Apply every patch selected for <version> of <shell>, in series order, with
# `patch -p0` from the current directory (the extracted source root). Takes the
# shell and resolves the set through shvr_patchset, so the ash/hush -> busybox
# mapping is stated once and shared with shvr_recipe_files -- were the call site
# to name the set itself, the patches applied and the patches hashed into the OID
# could drift apart.
#
# A failure aborts the build (set -e): a patch that no longer applies is a recipe
# bug, never something to skip.
shvr_apply_patches ()
{
	shvr_patch_list "$(shvr_patchset "$1")" "$2" |
		while IFS= read -r ap_file
		do
			echo "shvr: applying ${ap_file##*/}" >&2
			patch -p0 --no-backup-if-mismatch < "$ap_file"
		done
}
