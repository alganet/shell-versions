#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

set -euf

SHVR_DIR_SELF="$(cd "$(dirname "$0")"; pwd)"
SHVR_DIR_SRC="${SHVR_DIR_SRC:-"${SHVR_DIR_SELF}/build"}"
SHVR_DIR_OUT="${SHVR_DIR_OUT:-"${SHVR_DIR_SELF}/out"}"
SHVR_CHECKSUMS_DIR="${SHVR_CHECKSUMS_DIR:-"${SHVR_DIR_SELF}/checksums"}"
# Default: verify by default; set SHVR_SKIP_VERIFY_SHA256=1 to disable verification
SHVR_SKIP_VERIFY_SHA256="${SHVR_SKIP_VERIFY_SHA256:-0}"
# How many newest lineages each versions/<shell>.current keeps (a shell may override
# per-shell via a shvr_current_count_<shell> hook). See shvr_regen_current.
SHVR_CURRENT_LINEAGES="${SHVR_CURRENT_LINEAGES:-2}"

# shvr_patchset / shvr_patch_list / shvr_apply_patches. Sourced here because
# shvr_recipe_files resolves a target's patches without sourcing its variant;
# the variants that patch source it again, by literal path, so that the patch
# engine lands in their OID (see the note in common/patches.sh).
. "${SHVR_DIR_SELF}/common/patches.sh"

shvr ()
{
	mkdir -p "${SHVR_DIR_SRC}"
	mkdir -p "${SHVR_DIR_OUT}"
	# Allow hyphen or underscore in command names: normalize to underscore
	cmd="$1"
	shift || true
	cmd="$(echo "$cmd" | sed 's/-/_/g')"
	shvr_${cmd} "${@:-}"
}

shvr_build ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_buildset))
	fi

	set -x

	shvr_each build "${@:-}"
	shvr_generate_build_checksums "${@:-}"
}

# List supported targets (optionally limited to the given <shell> args) that have NO
# committed build checksums for the current arch — i.e. new versions surfaced by
# `update`. shvr_build_identity prints MISSING for exactly these; we check the dir
# directly (cheaper than computing the identity hash). One <shell>_<version> per line.
shvr_updated_targets ()
{
	bcd="$(shvr_build_checksums_dir)"
	for t in $(shvr_buildset "$@")
	do
		if ! test -d "${bcd}/${t}"
		then printf '%s\n' "$t"
		fi
	done
}

# The update-PR unit for a shell: its SOURCE, so shells built from one tree share
# one PR (and one build). ash and hush both declare busybox via
# shvr_versionsource_<shell> (see variants/ash.sh), so both map to "busybox";
# every other shell owns its source and maps to itself. This is the same hook the
# version machinery already keys off, so groups never drift from how trees build.
# Subshell: the variant is sourced on demand (like every other generic command
# here) so the hook is visible, without leaking its definitions to the caller.
shvr_group_of ()
(
	if test -f "${SHVR_DIR_SELF}/variants/$1.sh"
	then . "${SHVR_DIR_SELF}/variants/$1.sh"
	fi
	if command -v "shvr_versionsource_$1" >/dev/null 2>&1
	then "shvr_versionsource_$1"
	else echo "$1"
	fi
)

# One line per source-group that has a new version for the current SHVR_ARCH:
#   <group> <shell> [<shell>...]
# The shells are those in the group with at least one updated target; the group
# key is shvr_group_of. Drives the per-group matrix of the update-PR workflow:
# one line -> one PR. A shell's released bump and its snapshot bump are both
# <shell> targets, so they collapse into the same group (one PR carries both).
# Optional <shell> args narrow the scan (a manual, single-group run); no args =
# every changed group (the cron default). Groups and their shells come out in
# first-seen order, so the output is stable for a given updated-target set.
shvr_updated_groups ()
{
	# Reduce the updated targets to their DISTINCT shells first (a shell with
	# both a release and a snapshot bump appears twice), so shvr_group_of -- which
	# sources the shell's variant and its common/*.sh -- runs once per shell, not
	# once per target. Then emit "<group> <shell>" and let awk fold shells into
	# their group in first-seen order.
	shells_seen=" "
	for t in $(shvr_updated_targets "$@")
	do
		sh_name="${t%%_*}"
		case "$shells_seen" in *" $sh_name "*) continue ;; esac
		shells_seen="${shells_seen}${sh_name} "
		printf '%s %s\n' "$(shvr_group_of "$sh_name")" "$sh_name"
	done | awk '
		{
			# Shells are already distinct, so each group accumulates its members
			# in first-seen order. Test membership BEFORE assigning shells[$1]:
			# referencing it on a statement LHS vivifies it, so a same-statement
			# (in) test would always be true and prepend a stray leading space.
			if ($1 in shells) { shells[$1] = shells[$1] " " $2 }
			else { order[++n] = $1; shells[$1] = $2 }
		}
		END { for (i = 1; i <= n; i++) print order[i] " " shells[order[i]] }
	'
}

# Remove committed build-checksum dirs for targets no longer supported. The keep set is
# always the full current build set — shvr_buildset (released + pre-release), plus
# shvr_testing when that command exists. Keying off shvr_buildset rather than
# shvr_targets matters: a lane absent from the keep set would have its committed
# checksums reaped here and then fail CI's verify. A dropped version is dropped for every
# arch, so reap across all checksums/build/<arch>/ trees. Build checksums only;
# checksums/sources/ is left untouched. Prints the number of dirs pruned. (set -f is on,
# so globs do not expand — enumerate dirs with find, as the rest of the tree does.)
shvr_prune_build_checksums ()
{
	keep="$(shvr_buildset)"
	if command -v shvr_testing >/dev/null 2>&1
	then keep="${keep}
$(shvr_testing)"
	fi

	keeplist="${TMPDIR:-/tmp}/shvr_prune_keep.$$"
	trap 'rm -f "$keeplist"' EXIT INT TERM
	printf '%s\n' $keep | sed '/^[[:space:]]*$/d' > "$keeplist"

	build_root="${SHVR_CHECKSUMS_DIR}/build"
	pruned=0
	if test -d "$build_root"
	then
		for arch_dir in $(find "$build_root" -mindepth 1 -maxdepth 1 -type d)
		do
			for target_dir in $(find "$arch_dir" -mindepth 1 -maxdepth 1 -type d)
			do
				t="$(basename "$target_dir")"
				if ! grep -Fxq "$t" "$keeplist"
				then
					rm -rf "$target_dir"
					echo "pruned $(basename "$arch_dir")/${t}" >&2
					pruned=$((pruned + 1))
				fi
			done
		done
	fi

	rm -f "$keeplist"
	trap - EXIT INT TERM
	echo "$pruned"
}

# `build_updated [<shell> ...]`: build every supported target with no committed build
# checksums yet (a new version from `update`), generating its checksums, then prune the
# checksum dirs of targets we no longer support. Mirrors the canonical download->build
# sequence (deps are assumed installed, as `shvr build` assumes). Build checksums are
# arch-sensitive: run under linux/amd64 (SHVR_ARCH=amd64) so they match the CI.
# Build, for one arch, the given targets in a linux/<arch> image and write that arch's
# committed build checksums from the image's /opt — the same build-then-extract-then-
# generate flow CI uses (.github/actions/generate-build-checksums). The whole Linux-only
# toolchain (apt deps, musl-cross-make, cargo) runs inside the container, so this works
# from a macOS host. The platform drives the Dockerfile's TARGETARCH→SHVR_ARCH, so the
# musl/Rust cross-targets match. Usage: shvr_build_updated_arch <arch> <target>...
shvr_build_updated_arch ()
(
	arch="$1"
	shift

	# Require explicit targets. Without this guard an empty list flows into
	# `docker build --build-arg TARGETS=""`, and inside the container
	# `shvr.sh build` with no args falls back to the WHOLE buildset (~300
	# targets, toolchain included) -- a full from-scratch rebuild masquerading
	# as "build the new versions". The intended entry point is shvr_build_updated
	# (no arch), which computes the targets; this helper is only ever called with
	# them. Fail loudly rather than silently rebuild everything.
	if test -z "$*"
	then
		echo "shvr_build_updated_arch: no targets given (usage: build_updated_arch <arch> <target>...)." >&2
		echo "  To build every new version, use: shvr.sh build_updated" >&2
		return 2
	fi

	tag="shvr-build-updated-${arch}"
	# Scratch dir for the extracted /opt, outside the repo so nothing is polluted.
	# Subshell function (parens) so this EXIT trap is scoped to the call.
	workdir="$(mktemp -d "${TMPDIR:-/tmp}/shvr_build_updated.XXXXXX")"
	trap 'rm -rf "$workdir"' EXIT INT TERM

	echo "build_updated[${arch}]: docker build (linux/${arch}) for: $*" >&2

	# Single-platform build loaded into the local engine so we can extract from it.
	# Optional layer-cache sources, one registry ref per word in
	# SHVR_BUILD_CACHE_FROM. Unset locally (podman/buildah ignores registry cache
	# anyway), so the local build is unchanged.
	cache_from_args=""
	for _ref in ${SHVR_BUILD_CACHE_FROM:-}
	do cache_from_args="${cache_from_args} --cache-from=${_ref}"
	done

	# Optional named build contexts, one `name=value` per word in
	# SHVR_BUILD_CONTEXTS. The load-bearing use is
	# `toolchain=docker-image://<ref>`: the Dockerfile's `FROM ... AS toolchain`
	# stage is REPLACED by that image, so musl-cross-make is never re-derived --
	# the same contract build-images.yml relies on, and the reason a cold
	# --cache-from is not enough (a cache miss silently recompiles the whole
	# toolchain in every build, ~15 min each). Unset locally, so the from-source
	# toolchain build is unchanged there.
	build_context_args=""
	for _ctx in ${SHVR_BUILD_CONTEXTS:-}
	do build_context_args="${build_context_args} --build-context=${_ctx}"
	done

	# shellcheck disable=SC2086
	docker buildx build \
		--platform "linux/${arch}" \
		--build-arg TARGETS="$*" \
		$cache_from_args \
		$build_context_args \
		--load \
		-t "$tag" \
		"${SHVR_DIR_SELF}"

	# Extract /opt and (re)generate this arch's checksums from it, like CI does.
	container="$(docker create --platform "linux/${arch}" "$tag")"
	docker cp "${container}:/opt" "${workdir}/opt"
	docker rm -f "$container" >/dev/null

	# Subshell: point SHVR_ARCH/SHVR_DIR_OUT at this build without leaking the override.
	# shvr_build_checksums_dir then selects checksums/build/<arch>/ for the generate.
	(
		SHVR_ARCH="$arch"
		SHVR_DIR_OUT="${workdir}/opt"
		shvr_generate_build_checksums "$@"
	)

	echo "build_updated[${arch}]: wrote checksums/build/${arch}/" >&2
)

# `build_updated [<shell> ...]`: bring committed checksums up to date for every new
# version surfaced by `update`. It (1) fetches the new targets' sources and mints their
# SOURCE checksums (new versions have none committed yet — e.g. new bash patches — so the
# fetch skips verification, then we generate them), then (2) for EACH arch (default
# amd64 + arm64; override with SHVR_BUILD_ARCHES) builds the arch's missing targets in a
# linux/<arch> container and writes that arch's BUILD checksums, and (3) prunes checksum
# dirs for unsupported targets. Hands-off locally; reused by CI by setting
# SHVR_BUILD_ARCHES=<one arch> per native runner, then committing/PRing the result.
shvr_build_updated ()
{
	arches="${SHVR_BUILD_ARCHES:-amd64 arm64}"

	# Union of targets missing in ANY requested arch — these need their sources fetched.
	# shvr_updated_targets keys off SHVR_ARCH, so scope each in a subshell.
	all_new=""
	for arch in $arches
	do
		all_new="${all_new}
$( SHVR_ARCH="$arch"; export SHVR_ARCH; shvr_updated_targets "$@" )"
	done
	all_new="$(printf '%s\n' $all_new | sed '/^[[:space:]]*$/d' | sort -u)"

	if test -z "$all_new"
	then echo "build_updated: no new versions" >&2
	else
		echo "build_updated: new versions -> $(printf '%s ' $all_new)" >&2
		# New versions have no committed source checksums yet, so fetch without
		# verifying, then mint them (needed by the build and by CI's single-download).
		# Sources are arch-independent, so do this once for the whole union.
		( SHVR_SKIP_VERIFY_SHA256=1; export SHVR_SKIP_VERIFY_SHA256; shvr_download $all_new )
		shvr_generate_source_checksums $all_new
	fi

	for arch in $arches
	do
		new_arch="$( SHVR_ARCH="$arch"; export SHVR_ARCH; shvr_updated_targets "$@" )"
		if test -z "$new_arch"
		then echo "build_updated[${arch}]: nothing to build" >&2
		else shvr_build_updated_arch "$arch" $new_arch
		fi
	done

	n_pruned="$(shvr_prune_build_checksums)"
	echo "build_updated: pruned ${n_pruned} stale checksum dir(s)" >&2
}


shvr_deps ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_buildset))
	fi

	set -x

	shvr_each deps "${@:-}"
}

shvr_download ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_buildset))
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

# The pre-release lane as a set of its own, symmetric with the snapshot lane. Reads
# versions/<shell>.prerelease by default -- a shell opts in simply by having the file,
# so no per-variant boilerplate. A variant overrides shvr_prerelease_<shell> only when
# its versions come from somewhere else: ash/hush carry no list and derive busybox's,
# rewriting the prefix, exactly as they do for targets/current.
#
# Deliberately NOT part of shvr_targets: targets means "released versions" and feeds the
# :all assembly list, while this set feeds :all *and* the build/tag consumers. See
# shvr_buildset.
shvr_prerelease ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_interpreters))
	fi

	for pr_interpreter in "$@"
	do
		. "${SHVR_DIR_SELF}/variants/${pr_interpreter}.sh"
		if command -v "shvr_prerelease_${pr_interpreter}" >/dev/null 2>&1
		then "shvr_prerelease_${pr_interpreter}"
		else shvr_read_versions "${pr_interpreter}" prerelease
		fi
	done
}

# The development snapshot lane: the code that will become each shell's next version,
# pinned to a commit. Same shape as shvr_prerelease -- reads versions/<shell>.snapshot
# by default, so a shell opts in by having the file; a variant overrides
# shvr_snapshot_<shell> only when its versions come from elsewhere (ash/hush derive
# busybox's and rewrite the prefix).
#
# Snapshots are built and published as their own <shell>_snapshot-<shortsha> tag, and
# are never assembled into :all or :latest -- see shvr_buildset.
shvr_snapshot ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_interpreters))
	fi

	for sn_interpreter in "$@"
	do
		. "${SHVR_DIR_SELF}/variants/${sn_interpreter}.sh"
		if command -v "shvr_snapshot_${sn_interpreter}" >/dev/null 2>&1
		then "shvr_snapshot_${sn_interpreter}"
		else shvr_read_versions "${sn_interpreter}" snapshot
		fi
	done
}

# Everything we build and publish as its own <shell>_<version> tag: the released
# versions, plus the pre-release lane, plus the snapshot lane. This -- not
# shvr_targets -- is what every consumer that builds, downloads, patches, checksums,
# prunes or tags must use, so a lane cannot be silently dropped from the build by being
# absent from one of them.
#
# The :all assembly list is deliberately NOT this set: it composes shvr_targets +
# shvr_prerelease explicitly, so the snapshot lane is built and tagged without ever
# leaking into :all. The warm-sources download list does the same, for its own reason
# (see shvr_github_regen_downloads).
shvr_buildset ()
{
	shvr_targets "$@"
	shvr_prerelease "$@"
	shvr_snapshot "$@"
}

# Print the patches that apply to each <shell>_<version>, in apply order, as
# repo-relative paths. This is how you reproduce a tree by hand, without shvr:
#
#	tar xf yash-2.30.tar.xz && cd yash-2.30
#	for p in $(sh shvr.sh patches yash_2.30); do patch -p0 < "$OLDPWD/$p"; done
shvr_patches ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_buildset))
	fi

	for target in "$@"
	do
		shvr_patch_list "$(shvr_patchset "${target%%_*}")" "${target#*_}" |
			sed "s#^${SHVR_DIR_SELF}/##"
	done
}

# Check every patch set for drift against the versions it claims to patch.
# Catches the migration mistakes that would otherwise only surface as a failed
# build (a typo'd selector) or as silent under-patching (a version quietly
# dropped from a band).
shvr_check_patches ()
{
	rc=0

	for pset in $(find "${SHVR_DIR_SELF}/patches" -mindepth 1 -maxdepth 1 -type d |
		sed 's#.*/##' | sort)
	do
		pdir="${SHVR_DIR_SELF}/patches/${pset}"

		if ! test -f "${pdir}/series"
		then
			echo "check_patches: ${pset}: no series file (pre-series layout)" >&2
			continue
		fi

		# The version tokens a selector may legally name. A patch set is named
		# after the source it patches, which is also what versions/<name>.all is
		# keyed by -- ash and hush both build busybox, and it is versions/
		# busybox.all that lists their versions (neither has a list of its own).
		# Every lane we build, so a selector aimed at a pre-release or a snapshot is
		# not misreported as drift. A snapshot selector can only sensibly be a glob
		# (snapshot-*), since the token rolls on every update.
		known="$( { shvr_read_versions "$pset" all
			shvr_read_versions "$pset" prerelease
			shvr_read_versions "$pset" snapshot; } | sed "s/^${pset}_//")"

		if test -z "$known"
		then
			echo "check_patches: ${pset}: no versions/${pset}.all to check selectors against" >&2
			rc=1
			continue
		fi

		# Every patch a selector picks for a known version must exist, and every
		# version a selector names must be a version we actually build.
		sed -e ':x' -e '/\\$/{N;s/\\\n//;bx' -e '}' "${pdir}/series" |
			while IFS= read -r line
			do
				case "$line" in
				''|'#'*) continue ;;
				esac

				# shellcheck disable=SC2086
				set -- $line
				pfile="$1"
				shift

				if ! test -f "${pdir}/${pfile}"
				then
					echo "check_patches: ${pset}: series names a missing patch: ${pfile}" >&2
					exit 1
				fi

				for pat in "$@"
				do
					matched=0
					# shellcheck disable=SC2086
					for v in $known
					do
						case "$v" in
						$pat) matched=1; break ;;
						esac
					done

					if test "$matched" = 0
					then
						echo "check_patches: ${pset}: selector '${pat}' (${pfile}) matches no known version" >&2
						exit 1
					fi
				done
			done || rc=1

		# Every .diff in the directory must be reachable from the series file,
		# or it is dead weight nobody applies.
		for pfile in $(find "$pdir" -maxdepth 1 -name '*.diff' | sed 's#.*/##' | sort)
		do
			if ! sed -e ':x' -e '/\\$/{N;s/\\\n//;bx' -e '}' "${pdir}/series" |
				grep -qE "^[[:space:]]*${pfile}[[:space:]]"
			then
				echo "check_patches: ${pset}: ${pfile} is not referenced by series" >&2
				rc=1
			fi
		done
	done

	if test "$rc" = 0
	then echo "check_patches: ok"
	fi

	return "$rc"
}

shvr_update ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_interpreters))
	fi

	# One shell's upstream being unreachable must not sink the whole run: with a
	# dozen sources (flaky mirrors, a host that blocks GitHub's runner IPs, a
	# transient TLS timeout), an abort would strand every OTHER shell's genuine
	# updates and, in the update-PR workflow, open no PRs at all. So every network
	# step below is caught and turned into a warning + skip; the discovery helpers
	# and shvr_merge_* already refuse-to-overwrite on empty input, so a skip keeps
	# the committed versions intact rather than corrupting them. Skipped shells are
	# summarised at the end; the run still exits 0 so partial progress lands.
	update_skipped=""

	while test $# -gt 0
	do
		interpreter="$1"
		. "${SHVR_DIR_SELF}/variants/${interpreter}.sh"
		if command -v "shvr_update_${interpreter}" >/dev/null 2>&1
		then
			if ! "shvr_update_${interpreter}"
			then
				echo "update: ${interpreter}: release discovery failed; keeping committed versions" >&2
				update_skipped="${update_skipped} ${interpreter}"
			fi
			# Roll the snapshot lane for any shell that declares a channel. Central, so
			# a variant only names its repo/ref and never repeats the discovery dance.
			# `update` re-resolves the head every run, so the token rolls whenever
			# upstream moves; a failed resolve refuses to overwrite rather than
			# retiring the lane (see shvr_merge_snapshots).
			#
			# Roll the BACKING source, not the interpreter: ash and hush carry no
			# versions of their own and derive busybox's, rewriting the prefix, exactly
			# as shvr_regen_current_one does. Both of them resolve to busybox here, so
			# the second is a no-op.
			snapshot_src="${interpreter}"
			if command -v "shvr_versionsource_${interpreter}" >/dev/null 2>&1
			then snapshot_src="$("shvr_versionsource_${interpreter}")"
			fi
			if command -v "shvr_snapshotsource_${snapshot_src}" >/dev/null 2>&1
			then
				if ! shvr_discover_snapshot "${snapshot_src}" | shvr_merge_snapshots "${snapshot_src}"
				then echo "update: ${snapshot_src}: snapshot roll failed; keeping committed snapshot" >&2
				fi
			fi
			# Refresh versions/<shell>.current from the just-merged .all
			# (no-op for shells without their own .all, e.g. ash/hush).
			if ! shvr_regen_current_one "${interpreter}"
			then echo "update: ${interpreter}: regen_current failed" >&2
			fi
		else echo "skip: ${interpreter} has no updater yet" >&2
		fi
		shift
	done

	if test -n "$update_skipped"
	then echo "update: skipped (kept committed versions):${update_skipped}" >&2
	fi
}

# Regenerate versions/<shell>.current from versions/<shell>.all by keeping the newest
# N lineages. With no argument, regenerates every interpreter (the one-shot migration
# / drift-check entry point); ./shvr.sh regen_current [<shell> ...] routes here.
shvr_regen_current ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_interpreters))
	fi

	while test $# -gt 0
	do
		interpreter="$1"
		. "${SHVR_DIR_SELF}/variants/${interpreter}.sh"
		shvr_regen_current_one "${interpreter}"
		shift
	done
}

# Worker: rewrite a single versions/<shell>.current from its .all. The variant must
# already be sourced (so its shvr_current_lineage_<shell>/shvr_series_<shell> hooks are
# visible). The lineage key is chosen as: a dedicated shvr_current_lineage_<shell>, else
# the .all-dedup hook shvr_series_<shell>, else identity (each version its own lineage).
# shvr_filter_latest_per_series keeps the latest version per lineage, sorted descending;
# head -n N then keeps the newest N. .current is version-only (no date column).
shvr_regen_current_one ()
{
	interpreter="$1"
	file="${SHVR_DIR_SELF}/versions/${interpreter}.all"

	# Derived shells (ash/hush) carry no .all of their own: they back onto another
	# shell via shvr_versionsource_<shell> (e.g. busybox, whose hooks are already
	# sourced by the deriving variant). Regenerate the backing shell's .current — the
	# derived ones inherit it at read time through their busybox_->ash_ rewrite.
	if ! test -f "$file"
	then
		if command -v "shvr_versionsource_${interpreter}" >/dev/null 2>&1
		then shvr_regen_current_one "$("shvr_versionsource_${interpreter}")"
		fi
		return 0
	fi

	if command -v "shvr_current_lineage_${interpreter}" >/dev/null 2>&1
	then keyfn="shvr_current_lineage_${interpreter}"
	elif command -v "shvr_series_${interpreter}" >/dev/null 2>&1
	then keyfn="shvr_series_${interpreter}"
	else keyfn="shvr_identity_line"
	fi

	if command -v "shvr_current_count_${interpreter}" >/dev/null 2>&1
	then count="$("shvr_current_count_${interpreter}")"
	else count="${SHVR_CURRENT_LINEAGES}"
	fi

	current="${SHVR_DIR_SELF}/versions/${interpreter}.current"
	tmp="${current}.tmp.$$"

	# Strip the date column / comments / blanks (same idiom as shvr_read_versions),
	# collapse to the latest per lineage, then keep the newest N lineages.
	sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' -e 's/[[:space:]].*$//' "$file" |
		shvr_filter_latest_per_series "$keyfn" |
		head -n "$count" > "$tmp"

	if test -f "$current" && cmp -s "$tmp" "$current"
	then
		rm -f "$tmp"
		echo "${interpreter}.current: no change" >&2
	else
		mv "$tmp" "$current"
		echo "${interpreter}.current: updated" >&2
	fi
}

# Identity lineage key: every version is its own lineage (fallback when a shell has no
# lineage hook ⇒ .current is simply the newest N versions of .all).
shvr_identity_line ()
{
	printf '%s\n' "$1"
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
		# Allow keeping the extracted build tree for debugging when
		# SHVR_KEEP_BUILD=1. Otherwise clean it after each individual build.
		if test $subcommand = "build" && test "${SHVR_KEEP_BUILD:-0}" != "1"
		then
			rm -Rf "${SHVR_DIR_SRC}/${interpreter}/$version"
		fi
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

shvr_untar()
{
	tar --extract \
		--file="$1" \
		--strip-components=1 \
		--directory="$2" \
		--owner=0 \
		--group=0 \
		--mode=go-w
}

# Return 0 if <version> carries a pre-release marker. One canonical detector,
# shared by discovery (shvr_update_<shell>) and the .prerelease merge, so they
# agree on what counts as a pre-release. Matches the hyphenated suffix forms the
# upstreams use -- bash's bash-5.3-rc2 / -alpha / -beta, zsh's zsh-x.y-test, etc.
# A released lettered baseline like bash 2.05b is NOT a pre-release (the letter is
# part of the version, and there is no "-<word>" suffix), so it is left alone.
shvr_is_prerelease ()
{
	case "$1" in
	*-[Rr][Cc]*|*-[Aa][Ll][Pp][Hh][Aa]*|*-[Bb][Ee][Tt][Aa]*|\
	*-[Pp][Rr][Ee]*|*-[Tt][Ee][Ss][Tt]*|*-[Dd][Ee][Vv]*|*-[Ss][Nn][Aa][Pp][Ss][Hh][Oo][Tt]*)
		return 0 ;;
	*) return 1 ;;
	esac
}

# Return 0 if <version> is a development snapshot token (snapshot-<shortsha>).
# Canonical detector for the snapshot lane, as shvr_is_prerelease is for its own.
#
# The two can never collide, which is why both can key off the bare version token:
# every pre-release keyword needs a letter outside hex -- rc needs r, alpha needs
# l/p/h, beta needs t, pre needs p/r, test needs t/s, dev needs v, snapshot needs
# s/n/p/o -- so a hex short-sha cannot spell any of them.
shvr_is_snapshot ()
{
	case "$1" in
	snapshot-*) return 0 ;;
	*) return 1 ;;
	esac
}

shvr_read_versions ()
{
	interpreter="$1"
	which="$2"
	file="${SHVR_DIR_SELF}/versions/${interpreter}.${which}"
	# versions/<shell>.all carries a "<version> <date>" second column; strip it
	# so build/target ids stay <shell>_<version>. Harmless on the version-only
	# .current / .excluded files (no whitespace to strip).
	if test -f "$file"
	then sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' -e 's/[[:space:]].*$//' -e "s/^/${interpreter}_/" "$file"
	fi
}

shvr_filter_latest_per_series ()
{
	keyfn="$1"
	while IFS= read -r ver
	do
		if key="$("$keyfn" "$ver" 2>/dev/null)" && test -n "$key"
		then printf '%s\t%s\n' "$key" "$ver"
		fi
	done |
		sort -V -r |
		awk -F '\t' '!seen[$1]++ { print $2 }'
}

# Drop excluded versions from a stream of bare versions. Each non-comment line
# of <excluded_file> is "<version> [arch]": the version is always dropped; the
# optional second field records which arch the version fails on (metadata only,
# e.g. "arm64" or "amd64"). Exclusions are pooled across arches on purpose — the
# published all/latest lists are identical on every arch (a version unbuildable
# on any arch is dropped from all of them; the arch tag documents why, so a later
# fix can re-enable it). Matching is on the first field so an arch tag does not
# defeat the exclusion.
shvr_filter_excluded ()
{
	excluded_file="$1"
	if test -s "$excluded_file"
	then
		pat="${TMPDIR:-/tmp}/shvr_excl.$$"
		awk '!/^[[:space:]]*#/ && NF { print $1 }' "$excluded_file" > "$pat"
		if test -s "$pat"
		then grep -v -F -x -f "$pat"
		else cat
		fi
		rm -f "$pat"
	else cat
	fi
}

shvr_merge_versions ()
{
	interpreter="$1"
	file="${SHVR_DIR_SELF}/versions/${interpreter}.all"
	mkdir -p "$(dirname "$file")"

	if ! test -f "$file"
	then : > "$file"
	fi

	excluded_file="${SHVR_DIR_SELF}/versions/${interpreter}.excluded"

	# Subshell so the EXIT trap is function-scoped (POSIX traps are
	# process-scoped otherwise).
	(
		tmp="${file}.tmp.$$"
		discovered="${tmp}.discovered"
		existing="${tmp}.existing"
		excluded="${tmp}.excluded"
		versions="${tmp}.versions"
		datemap="${tmp}.datemap"
		merged="${tmp}.merged"
		existing_v="${tmp}.existing_v"
		new_only="${tmp}.new"
		dropped="${tmp}.dropped"

		trap 'rm -f "$discovered" "$existing" "$excluded" "$versions" "$datemap" "$merged" "$existing_v" "$new_only" "$dropped"' EXIT INT TERM

		cat > "$discovered"

		if ! test -s "$discovered"
		then
			echo "${interpreter}: no versions discovered (upstream fetch may have failed); refusing to overwrite ${file}" >&2
			exit 1
		fi

		sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' "$file" > "$existing"

		if test -f "$excluded_file"
		then sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' "$excluded_file" > "$excluded"
		else : > "$excluded"
		fi

		if command -v "shvr_series_${interpreter}" >/dev/null 2>&1
		then series_filter="shvr_filter_latest_per_series shvr_series_${interpreter}"
		else series_filter="cat"
		fi

		# Lines (existing and discovered) are "<version>" or "<version> <date>".
		# Work the set math on the bare version column so the exclude/series
		# filters stay date-agnostic, then re-attach dates from a version->date
		# map that prefers the committed (existing) date over the discovered one.

		# Union existing + discovered versions, drop excluded, dedupe to one
		# entry per series, sort descending by version.
		cat "$existing" "$discovered" |
			awk '{print $1}' |
			shvr_filter_excluded "$excluded" |
			$series_filter |
			sort -V -u -r > "$versions"

		# version->date map: existing dates win, discovered fills the gaps.
		cat "$existing" "$discovered" |
			awk 'NF >= 2 && !($1 in d) { d[$1] = $2; print $1, $2 }' > "$datemap"

		# Re-attach dates, preserving the version sort order.
		awk 'NR == FNR { d[$1] = $2; next }
			{ if ($1 in d) print $1, d[$1]; else print $1 }' \
			"$datemap" "$versions" > "$merged"

		# $versions is already the bare, sorted version column of $merged.
		awk '{print $1}' "$existing" > "$existing_v"

		if test -s "$existing_v"
		then grep -v -F -x -f "$existing_v" "$versions" > "$new_only" || true
		else cp "$versions" "$new_only"
		fi

		if test -s "$existing_v"
		then grep -v -F -x -f "$versions" "$existing_v" > "$dropped" || true
		else : > "$dropped"
		fi

		cp "$merged" "$file"

		if test -s "$new_only"
		then
			n_new=$(wc -l < "$new_only" | tr -d ' ')
			echo "${interpreter}: added ${n_new} new version(s):" >&2
			sed 's/^/  /' "$new_only" >&2
		fi

		if test -s "$dropped"
		then
			n_drop=$(wc -l < "$dropped" | tr -d ' ')
			echo "${interpreter}: dropped ${n_drop} version(s):" >&2
			sed 's/^/  /' "$dropped" >&2
		fi

		if ! test -s "$new_only" && ! test -s "$dropped"
		then echo "${interpreter}: no changes" >&2
		fi
	)
}

# Sibling of shvr_merge_versions for the pre-release channel. Reads a discovered
# "<version> [<date>]" stream on stdin and rewrites versions/<shell>.prerelease to
# hold the single newest pre-release token (dropping excluded ones). Unlike .all
# this list is NON-STICKY: it is rebuilt from scratch every update, so a newer rc
# rolls the entry forward and an upstream that no longer ships a pre-release
# empties it. We keep the newest pre-release outright -- no comparison against the
# stable list -- so "the last pre-release the shell had" survives even when a
# newer stable already exists (e.g. bash 5.3-rc2 alongside stable 5.3.x). The
# .prerelease list feeds :all through shvr_targets_<shell> but never :latest,
# because .current is regenerated from .all alone -- so a pre-release can never
# leak into the latest image.
shvr_merge_prereleases ()
{
	interpreter="$1"
	file="${SHVR_DIR_SELF}/versions/${interpreter}.prerelease"
	excluded_file="${SHVR_DIR_SELF}/versions/${interpreter}.excluded"
	mkdir -p "$(dirname "$file")"

	(
		tmp="${file}.tmp.$$"
		excl="${tmp}.excl"
		trap 'rm -f "$tmp" "$excl"' EXIT INT TERM

		if test -f "$excluded_file"
		then awk '!/^[[:space:]]*#/ && NF { print $1 }' "$excluded_file" > "$excl"
		else : > "$excl"
		fi

		# Keep only pre-release tokens, drop excluded, sort newest-first, keep one.
		while IFS= read -r line
		do
			ver="${line%%[[:space:]]*}"
			test -n "$ver" || continue
			shvr_is_prerelease "$ver" || continue
			if test -s "$excl" && grep -Fxq "$ver" "$excl"
			then continue
			fi
			printf '%s\n' "$line"
		done | sort -V -r | head -n1 > "$tmp"

		if test -f "$file" && cmp -s "$tmp" "$file"
		then echo "${interpreter}.prerelease: no change" >&2
		else
			mv "$tmp" "$file"
			if test -s "$file"
			then echo "${interpreter}.prerelease: $(cat "$file")" >&2
			else echo "${interpreter}.prerelease: (none)" >&2
			fi
		fi
		# The EXIT trap cleans $excl (and $tmp, already moved on the write path).
	)
}

# Resolve <shell>'s snapshot channel to a "snapshot-<shortsha> <fullsha>" line, using
# the "<repo> <ref>" its variant declares via shvr_snapshotsource_<shell>. Prints nothing
# for a shell with no channel.
#
# Both columns are load-bearing. The short sha is the version token: it names the target
# and the published tag. But it cannot fetch the tree -- `git fetch <sha>` requires the
# full 40-hex object id and servers refuse an abbreviation ("couldn't find remote ref")
# -- and the branch head cannot simply be re-resolved at build time, because it moves,
# which would silently build a different tree than the token names. So the full sha rides
# along as the fetch pin. The two roll together in one commit, so any checkout of this
# repo has a token and a pin that agree.
shvr_discover_snapshot ()
{
	sn_interpreter="$1"
	# Source the variant so the hook is visible when called directly; shvr_update has
	# already sourced it, and sourcing twice is harmless. Guarded because the argument
	# may be a backing source rather than an interpreter: busybox has no variant of its
	# own (ash/hush deriving it source common/busybox.sh, where its hooks live).
	if test -f "${SHVR_DIR_SELF}/variants/${sn_interpreter}.sh"
	then . "${SHVR_DIR_SELF}/variants/${sn_interpreter}.sh"
	fi
	command -v "shvr_snapshotsource_${sn_interpreter}" >/dev/null 2>&1 || return 0

	# Deliberate word split of the hook's "<repo> <ref>".
	# shellcheck disable=SC2046
	set -- $("shvr_snapshotsource_${sn_interpreter}")
	sn_repo="$1"
	sn_ref="$2"

	sn_sha="$(git ls-remote "$sn_repo" "refs/heads/${sn_ref}" 2>/dev/null | cut -f1)"
	if test -z "$sn_sha"
	then
		echo "${sn_interpreter}: could not resolve ${sn_ref} at ${sn_repo}" >&2
		return 1
	fi

	printf 'snapshot-%.12s %s\n' "$sn_sha" "$sn_sha"
}

# The full sha a snapshot token pins, from versions/<shell>.snapshot's second column.
# The token itself carries only the short sha (it has to be a tag); see
# shvr_discover_snapshot. Usage: shvr_snapshot_sha <shell> <version>
shvr_snapshot_sha ()
{
	sn_interpreter="$1"
	sn_version="$2"
	sn_file="${SHVR_DIR_SELF}/versions/${sn_interpreter}.snapshot"

	sn_full="$(awk -v v="$sn_version" '$1 == v { print $2; exit }' "$sn_file" 2>/dev/null)"
	if test -z "$sn_full"
	then
		echo "shvr_snapshot_sha: ${sn_interpreter}: no pinned sha for ${sn_version} in ${sn_file}" >&2
		return 1
	fi

	printf '%s\n' "$sn_full"
}

# Fetch <shell>'s snapshot tree at its pinned sha and archive it into <dest> -- the
# tarball that shell's build already knows how to unpack, so no shvr_build_<shell> has to
# change. Shallow, so it costs one commit rather than the project's whole history.
#
# The WHOLE snapshot lane fetches this way, including shells whose forge would serve an
# archive at that sha. Git verifies the object hash against the sha committed in
# versions/<shell>.snapshot: a real cryptographic check of exactly the tree we named. A
# forge tarball could only be checked against a sha256 we minted ourselves, and those
# tarballs are not byte-stable (a regenerated one can fail its own committed checksum on
# content that is perfectly correct). One code path, one guarantee, and no source
# checksums to mint, verify or reap.
#
# The archive's own bytes are therefore not reproducible and deliberately not checksummed
# -- git archive framing varies across git versions. What must be reproducible is the
# BUILD, and it is: the tree is fixed by the sha, so the compiled binary is, and its build
# checksums are committed and verified as for any other target.
#
# <dest>'s extension picks the compression, because that is what the build expects to
# unpack (zsh wants .tar.xz, busybox .tar.bz2, most want .tar.gz).
# Usage: shvr_snapshot_fetch_git <shell> <version> <dest> <prefix>
shvr_snapshot_fetch_git ()
{
	sn_interpreter="$1"
	sn_version="$2"
	sn_dest="$3"
	sn_prefix="$4"

	if test -f "$sn_dest"
	then return 0
	fi

	case "$sn_dest" in
	*.tar.gz)  sn_z=gzip  ;;
	*.tar.xz)  sn_z=xz    ;;
	*.tar.bz2) sn_z=bzip2 ;;
	*)
		echo "shvr_snapshot_fetch_git: unsupported archive form: ${sn_dest}" >&2
		return 1
		;;
	esac

	sn_full="$(shvr_snapshot_sha "$sn_interpreter" "$sn_version")"
	sn_repo="$("shvr_snapshotsource_${sn_interpreter}" | cut -d' ' -f1)"
	sn_tmp="$(mktemp -d "${TMPDIR:-/tmp}/shvr_snapshot.XXXXXX")"
	sn_work="${sn_tmp}/${sn_prefix}"

	mkdir -p "$(dirname "$sn_dest")" "$sn_work"
	git init -q "$sn_work"
	git -C "$sn_work" remote add origin "$sn_repo"
	# The full sha, not the short token: servers refuse an abbreviated object id.
	git -C "$sn_work" fetch -q --depth 1 origin "$sn_full"

	# Write via a temp so an interrupted fetch cannot leave a partial tarball behind to
	# be cached and unpacked.
	if git -C "$sn_work" cat-file -e FETCH_HEAD:.gitmodules 2>/dev/null
	then
		# git archive records a submodule as a bare gitlink and never its content, so a
		# tree with submodules has to be checked out, its submodules materialised, and
		# the worktree tarred instead. loksh is the case in point: its meson.build does
		# subproject('lolibc'), which upstream bundles into the release tarball but git
		# only references -- archiving it yields an empty subprojects/lolibc/ and meson
		# fails with "Subproject exists but has no meson.build file".
		git -C "$sn_work" checkout -q FETCH_HEAD
		git -C "$sn_work" submodule update --init --recursive --depth 1 -q
		tar --create --directory "$sn_tmp" --exclude-vcs --sort=name \
			--owner=0 --group=0 --numeric-owner --mtime='@1' "$sn_prefix" |
			"$sn_z" > "${sn_dest}.part"
	else
		git -C "$sn_work" archive --format=tar --prefix="${sn_prefix}/" FETCH_HEAD |
			"$sn_z" > "${sn_dest}.part"
	fi

	mv "${sn_dest}.part" "$sn_dest"
	rm -rf "$sn_tmp"
}

# Sibling of shvr_merge_prereleases for the snapshot lane. Reads a discovered
# "snapshot-<shortsha> [<date>]" line on stdin and rewrites versions/<shell>.snapshot.
# Non-sticky for the same reason: `shvr update` re-resolves the dev head every run, so
# the token rolls and the previous one is simply gone. Its build checksums are reaped by
# shvr_prune_build_checksums (the snapshot is in shvr_buildset's keep set only while it
# is current); its published tag and source checksum are THEREAPER.md's problem.
#
# Unlike the pre-release merge this does NOT sort: a sha has no order, and discovery
# yields exactly one line -- the resolved head. Taking the first is the whole selection.
shvr_merge_snapshots ()
{
	interpreter="$1"
	file="${SHVR_DIR_SELF}/versions/${interpreter}.snapshot"
	excluded_file="${SHVR_DIR_SELF}/versions/${interpreter}.excluded"
	mkdir -p "$(dirname "$file")"

	(
		tmp="${file}.tmp.$$"
		excl="${tmp}.excl"
		trap 'rm -f "$tmp" "$excl"' EXIT INT TERM

		if test -f "$excluded_file"
		then awk '!/^[[:space:]]*#/ && NF { print $1 }' "$excluded_file" > "$excl"
		else : > "$excl"
		fi

		while IFS= read -r line
		do
			ver="${line%%[[:space:]]*}"
			test -n "$ver" || continue
			shvr_is_snapshot "$ver" || continue
			if test -s "$excl" && grep -Fxq "$ver" "$excl"
			then continue
			fi
			printf '%s\n' "$line"
		done | head -n1 > "$tmp"

		# Same guard as shvr_merge_versions, and it matters more here: discovery is a
		# live `git ls-remote`, so a network blip yields nothing. Wiping the token on
		# empty input would drop the target from shvr_buildset, and prune would then
		# reap its committed build checksums. Refuse instead; a channel is retired by
		# deleting the file, not by a failed fetch.
		if ! test -s "$tmp"
		then
			echo "${interpreter}: no snapshot discovered (upstream fetch may have failed); refusing to overwrite ${file}" >&2
			exit 1
		fi

		if test -f "$file" && cmp -s "$tmp" "$file"
		then echo "${interpreter}.snapshot: no change" >&2
		else
			mv "$tmp" "$file"
			if test -s "$file"
			then echo "${interpreter}.snapshot: $(cat "$file")" >&2
			else echo "${interpreter}.snapshot: (none)" >&2
			fi
		fi
		# The EXIT trap cleans $excl (and $tmp, already moved on the write path).
	)
}

# Map an English month name to a zero-padded number, case-insensitively (the
# date sources emit title-case names like Sep/May).
shvr_month_num ()
{
	case "$1" in
	Jan|jan|JAN) printf '01' ;;
	Feb|feb|FEB) printf '02' ;;
	Mar|mar|MAR) printf '03' ;;
	Apr|apr|APR) printf '04' ;;
	May|may|MAY) printf '05' ;;
	Jun|jun|JUN) printf '06' ;;
	Jul|jul|JUL) printf '07' ;;
	Aug|aug|AUG) printf '08' ;;
	Sep|sep|SEP) printf '09' ;;
	Oct|oct|OCT) printf '10' ;;
	Nov|nov|NOV) printf '11' ;;
	Dec|dec|DEC) printf '12' ;;
	*) return 1 ;;
	esac
}

# Normalize a directory-listing date token to ISO YYYY-MM-DD. Accepts the ISO
# form (2022-09-26, passed through) and the GNU autoindex month-name form
# (2022-Sep-26). Returns 1 on anything else so callers can drop the date.
shvr_iso_date ()
{
	case "$1" in
	[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
		printf '%s' "$1"
		;;
	[0-9][0-9][0-9][0-9]-[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9])
		_y="${1%%-*}"
		_rest="${1#*-}"
		_mon="${_rest%%-*}"
		_day="${_rest##*-}"
		_m="$(shvr_month_num "$_mon")" || return 1
		printf '%s-%s-%s' "$_y" "$_m" "$_day"
		;;
	*) return 1 ;;
	esac
}

# Convert an RFC-822 date (RSS <pubDate>, e.g. "Sun, 31 May 2026 20:55:59 UT")
# to ISO YYYY-MM-DD. Subshell so `set --` does not clobber caller positionals.
shvr_iso_rfc822 ()
(
	# shellcheck disable=SC2086
	set -- $1
	# $1=weekday, $2=day, $3=month, $4=year
	_day="${2#0}"
	_m="$(shvr_month_num "$3")" || return 1
	printf '%s-%s-%02d' "$4" "$_m" "$_day"
)

# Print the recorded ISO date for <interpreter> <version>, or nothing if the
# version is absent or undated in versions/<interpreter>.all. Interpreters with
# no .all of their own (ash, hush reuse busybox) may declare a backing shell via
# a shvr_versionsource_<interpreter> hook in their variant; the variant is
# loaded on demand so this works even outside the per-shell dispatch.
shvr_version_date ()
{
	interpreter="$1"
	version="$2"
	if ! test -f "${SHVR_DIR_SELF}/versions/${interpreter}.all"
	then
		vf="${SHVR_DIR_SELF}/variants/${interpreter}.sh"
		if ! command -v "shvr_versionsource_${interpreter}" >/dev/null 2>&1 && test -f "$vf"
		then . "$vf"
		fi
		if command -v "shvr_versionsource_${interpreter}" >/dev/null 2>&1
		then interpreter="$("shvr_versionsource_${interpreter}")"
		fi
	fi
	file="${SHVR_DIR_SELF}/versions/${interpreter}.all"
	if test -f "$file"
	then awk -v v="$version" '$1 == v && NF >= 2 { print $2; exit }' "$file"
	fi
}

# Filter <shell>_<version> target ids on stdin to those released on or after
# SHVR_SINCE (ISO YYYY-MM-DD). With SHVR_SINCE unset, passes everything through.
# Undated targets are dropped with a warning rather than crashing.
shvr_filter_since ()
{
	since="${SHVR_SINCE:-}"
	if test -z "$since"
	then cat; return 0
	fi
	while IFS= read -r target
	do
		test -n "$target" || continue
		interpreter="${target%%_*}"
		version="${target#*_}"
		printf '%s\t%s\n' "$target" "$(shvr_version_date "$interpreter" "$version")"
	done |
		awk -F '\t' -v s="$since" '
			$2 == "" { print "shvr_filter_since: " $1 " has no date; dropping" > "/dev/stderr"; next }
			$2 >= s { print $1 }'
}

shvr_fetch()
{
	url="$1"
	dest="$2"

	mkdir -p "$(dirname "$dest")"

	if ! test -f "$dest"
	then
		if command -v curl >/dev/null 2>&1
		then
			curl -sSL -o "$dest" "$url" || return 1
		else
			echo "curl is required to download $url" >&2
			return 1
		fi
	fi

	if test "${SHVR_SKIP_VERIFY_SHA256}" = "1"
	then
		# skip verification when explicitly requested
		return 0
	fi

	# Only verify files under SHVR_DIR_SRC; for others derive from absolute
	# path by stripping leading slash and using that relative path in checksums.
	case "$dest" in
		${SHVR_DIR_SRC}/*)
			relpath="${dest#${SHVR_DIR_SRC}/}"
			;;
		/*)
			relpath="${dest#/}"
			;;
		*)
			relpath="$dest"
			;;
	esac

	checksum_file="${SHVR_CHECKSUMS_DIR}/sources/${relpath}.sha256sums"

	if ! test -f "$checksum_file"
	then
		echo "checksum missing for $dest, expected at $checksum_file" >&2
		return 1
	fi

	# Run verification: change to dest dir so relative filenames match
	savedir="$(pwd)"
	cd "$(dirname "$dest")"
	if ! sha256sum -c "$checksum_file" >/dev/null 2>&1
	then
		echo "sha256sum mismatch for $dest (checksum file: $checksum_file)" >&2
		cd "$savedir"
		return 1
	fi
	cd "$savedir"
	return 0
}

shvr_generate_checksums()
{

	start_dir="${SHVR_DIR_SRC}"

	find "$start_dir" -type f | while read -r f
	do
		rel="${f#${SHVR_DIR_SRC}/}"
		dest_dir="$(dirname "${SHVR_CHECKSUMS_DIR}/sources/${rel}.sha256sums")"
		mkdir -p "$dest_dir"
		# write a file containing one line with: <sha256>  basename
		sha256sum "$f" | sed "s/  .*/  $(basename "$f")/" > "${SHVR_CHECKSUMS_DIR}/sources/${rel}.sha256sums"
	done
}

# Generate SOURCE checksums (checksums/sources/) for specific targets — the per-target,
# scoped counterpart of shvr_generate_checksums (which hashes the entire build/ tree). A
# target's source artifacts are the downloaded files at build/<cache_path>.* and
# build/<cache_path>-* (the tarball, plus bash's numbered patches); the extracted tree
# build/<cache_path>/ is NOT a source, so the trailing-slash form is skipped. Used by
# build_updated to mint checksums for the new sources a version brings (e.g. bash patches
# 010-015), which have none committed yet. Usage: shvr_generate_source_checksums <t> ...
shvr_generate_source_checksums ()
{
	for t in "$@"
	do
		shvr_clear_versioninfo
		interpreter="${t%%_*}"
		version="${t#*_}"

		# The snapshot lane has no source checksums at all, on purpose. Every snapshot
		# is fetched from git at its pinned sha (shvr_snapshot_fetch_git) and archived
		# locally, so the download bypasses shvr_fetch and a sha256 here would never be
		# verified. It would also differ between machines -- `git archive` framing is not
		# byte-stable across git versions -- so committing one would assert a
		# reproducibility we do not have. Git's own object hashing already verifies the
		# tree against the sha in versions/<shell>.snapshot, which is the stronger check.
		# BUILD checksums are still committed and verified: they cover the compiled
		# binary, which the sha does fix.
		if shvr_is_snapshot "$version"
		then continue
		fi

		. "${SHVR_DIR_SELF}/variants/${interpreter}.sh"
		"shvr_versioninfo_${interpreter}" "$version"
		cp="${build_srcdir#${SHVR_DIR_SRC}/}"

		find "${SHVR_DIR_SRC}/${interpreter}" -type f 2>/dev/null | while IFS= read -r f
		do
			rel="${f#${SHVR_DIR_SRC}/}"
			case "$rel" in
				"${cp}".*|"${cp}"-*)
					dest="${SHVR_CHECKSUMS_DIR}/sources/${rel}.sha256sums"
					mkdir -p "$(dirname "$dest")"
					sha256sum "$f" | sed "s/  .*/  $(basename "$f")/" > "$dest"
					;;
			esac
		done
	done
}


# Build checksums are arch-specific (compiled binaries differ per arch) and so
# live under checksums/build/<arch>/, selected by SHVR_ARCH (default amd64, the
# arch the legacy unscoped tree was migrated to). Source checksums stay shared
# (tarballs are arch-independent). One arch is ever materialized in a given build
# container, so SHVR_DIR_OUT/SHVR_DIR_SRC carry no arch segment — only the
# committed checksum tree does.
shvr_build_checksums_dir ()
{
	echo "${SHVR_CHECKSUMS_DIR}/build/${SHVR_ARCH:-amd64}"
}

# Generate checksums for build outputs under ${SHVR_DIR_OUT} and write them to
# $(shvr_build_checksums_dir)/<rel>.sha256sums mirroring the out layout.
# Usage: shvr_generate_build_checksums [<shell>_<version> ...]
shvr_generate_build_checksums()
{
	bcd="$(shvr_build_checksums_dir)"
	if test -z "$*"
	then
		start_dir="${SHVR_DIR_OUT}"
		find "$start_dir" -type f -not -path '*/shvr/*' | while read -r f
		do
			rel="${f#${SHVR_DIR_OUT}/}"
			dest_dir="$(dirname "${bcd}/${rel}.sha256sums")"
			mkdir -p "$dest_dir"
			sha256sum "$f" | sed "s/  .*/  $(basename "$f")/" > "${bcd}/${rel}.sha256sums"
		done
	else
		# Only generate checksums for specific targets (e.g., bash_5.3.9)
		for t in "$@"
		do
			dir="$SHVR_DIR_OUT/${t}"
			if test -d "$dir"
			then
				find "$dir" -type f | while read -r f
				do
					rel="${f#${SHVR_DIR_OUT}/}"
					dest_dir="$(dirname "${bcd}/${rel}.sha256sums")"
					mkdir -p "$dest_dir"
					sha256sum "$f" | sed "s/  .*/  $(basename "$f")/" > "${bcd}/${rel}.sha256sums"
				done
			fi
		done
	fi
}

# Verify build outputs against committed checksums in ${SHVR_CHECKSUMS_DIR}/build/.
# Reports all failures before exiting so CI logs show every mismatch.
# Usage: shvr_verify_build_checksums [<shell>_<version> ...]
shvr_verify_build_checksums()
{
	if test "${SHVR_SKIP_VERIFY_SHA256}" = "1"
	then
		return 0
	fi

	checksums_dir="$(shvr_build_checksums_dir)"

	if ! test -d "$checksums_dir"
	then
		echo "no build checksums directory at $checksums_dir" >&2
		return 1
	fi

	fail_count=0

	if test -z "$*"
	then
		search_dir="$checksums_dir"
	else
		search_dir=""
		for t in "$@"
		do
			target_dir="${checksums_dir}/${t}"
			if ! test -d "$target_dir"
			then
				echo "no build checksums for target $t at $target_dir" >&2
				fail_count=$((fail_count + 1))
				continue
			fi
			search_dir="${search_dir} ${target_dir}"
		done
	fi

	for d in $search_dir
	do
		for checksum_file in $(find "$d" -name '*.sha256sums')
		do
			rel="${checksum_file#${checksums_dir}/}"
			# Strip .sha256sums suffix to get the relative path of the binary
			bin_rel="${rel%.sha256sums}"
			bin_path="${SHVR_DIR_OUT}/${bin_rel}"

			if ! test -f "$bin_path"
			then
				echo "FAIL missing binary: $bin_path (expected by $checksum_file)" >&2
				fail_count=$((fail_count + 1))
				continue
			fi

			savedir="$(pwd)"
			cd "$(dirname "$bin_path")"
			if ! sha256sum -c "$checksum_file" >/dev/null 2>&1
			then
				expected=$(cat "$checksum_file")
				actual=$(sha256sum "$(basename "$bin_path")" | sed "s/  .*/  $(basename "$bin_path")/")
				echo "FAIL $bin_rel" >&2
				echo "  expected: $expected" >&2
				echo "  actual:   $actual" >&2
				fail_count=$((fail_count + 1))
			fi
			cd "$savedir"
		done
	done

	if test "$fail_count" -gt 0
	then
		echo "build checksum verification failed: $fail_count error(s)" >&2
		return 1
	fi
}

shvr_github_regen_downloads ()
{
	# Released + pre-release, NOT shvr_buildset. This action has exactly one consumer,
	# warm-sources.yml, whose job is to keep long-lived source caches from being evicted
	# so a rarely-rebuilt target can still be rebuilt. A snapshot source is worth nothing
	# there: it is fetched once by the build that mints it, and the moment its sha rolls
	# it is superseded and never wanted again. Composed explicitly so the snapshot lane
	# can join shvr_buildset without silently being warmed forever.
	set -- $(printf '%s ' $( { shvr_targets; shvr_prerelease; } | sort -t'_' -k1,1 -k2Vr))
	local yml_file="${SHVR_DIR_SELF}/.github/actions/downloads/action.yml"
	cp -f "$yml_file" "${yml_file}.bak"
	IFS=
	cat "$yml_file.bak" |
	{
		while read -r yml_line
		do
			printf '%s\n' "${yml_line}"
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


shvr_github_regen_docker_workflow ()
{
	local yml_file="${SHVR_DIR_SELF}/.github/workflows/docker.yml"
	# The :all image is released + pre-release. Deliberately composed here instead of
	# reusing shvr_buildset, so a later lane (snapshots) can join the build set -- and
	# get built and tagged -- without ever leaking into :all.
	local all_targets="$(printf '%s ' $( { shvr_targets; shvr_prerelease; } | sort -t'_' -k1,1 -k2Vr))"
	local current_targets="$(printf '%s ' $(shvr_current | sort -t'_' -k1,1 -k2Vr))"
	cp -f "$yml_file" "${yml_file}.bak"
	cat "$yml_file.bak" |
	{
		# The per-target build matrix is no longer generated here: it is
		# dynamic (the plan job emits it via shvr_plan_matrix from each image's
		# OID annotation). This function only maintains the static assembly
		# flavor lists, so echo straight through to the assemblies marker.
		while IFS= read -r yml_line
		do
			printf '%s\n' "${yml_line}"
			case ${yml_line} in
				*'# AUTO-GENERATED ASSEMBLIES. DO NOT EDIT MANUALLY.'*)
					break
					;;
			esac
		done
		# Emit assembly matrix entries, fully specified (flavor + arch +
		# targets) per arch so the matrix needs no axis/include cross-product
		# (which GitHub Actions resolves ambiguously). One (flavor, arch) per
		# row; the assemble-manifest job fuses the two arches afterwards.
		for arch in amd64 arm64
		do
			echo "          - flavor: latest"
			echo "            arch: ${arch}"
			echo "            targets: >"
			for target in $current_targets
			do
				echo "              $target"
			done
			echo "          - flavor: all"
			echo "            arch: ${arch}"
			echo "            targets: >"
			for target in $all_targets
			do
				echo "              $target"
			done
		done
		# Skip old assembly entries until steps:
		while IFS= read -r yml_line
		do
			case ${yml_line} in
				'    steps:'*)
					break
					;;
			esac
		done
		# Echo steps and remaining content
		printf '%s\n' "${yml_line}"
		while IFS= read -r yml_line
		do
			printf '%s\n' "${yml_line}"
		done
	} > "$yml_file"
	rm "$yml_file.bak"
}

shvr_toolchain_download ()
{
	. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
	. "${SHVR_DIR_SELF}/common/rustup.sh"
	shvr_download_musl_cross_make
	shvr_download_rustup
}

# Fetch the shared build-dependency SOURCES (ncurses, readline, libedit, pcre1/2)
# that many shells link but that live outside any single target's cache_path, so
# per-target single-download never caches them and every build job would otherwise
# re-fetch them from their (flaky) upstreams. Downloaded once and cached by the
# common-downloads action, exactly as shvr_toolchain_download is by
# toolchain-downloads. Download-only: the untar/build stays in each shvr_build_*.
shvr_common_download ()
{
	. "${SHVR_DIR_SELF}/common/ncurses.sh"
	. "${SHVR_DIR_SELF}/common/readline.sh"
	. "${SHVR_DIR_SELF}/common/libedit.sh"
	. "${SHVR_DIR_SELF}/common/pcre.sh"
	shvr_download_ncurses
	shvr_download_readline
	shvr_download_libedit
	shvr_download_pcre1
	shvr_download_pcre2
}

shvr_musl_build ()
{
	. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
	apt-get -y install gcc g++ make curl patch xz-utils
	shvr_download_musl_cross_make
	shvr_build_musl_cross_make
}

shvr_github_regen_all ()
{
	(shvr_github_regen_downloads)
	(shvr_github_regen_docker_workflow)
}

# Toolchain fingerprint: a hash of the globally-pinned reproducibility inputs
# that are not expressed in any variant recipe file — the Debian base image
# digest, the apt snapshot, the Rust toolchain, and the rustup-init version (all
# from the Dockerfile). The musl and ncurses pins live inside
# common/musl-cross-make.sh / common/ncurses.sh, which are folded into per-target
# recipes instead (see shvr_recipe_files), so they need not be repeated here.
# RUNTIME_BASE is deliberately excluded: it does not affect the per-target
# `artifacts` stage. Folded into every build identity, so a pin bump forces a
# full rebuild; bump the OIDV scheme tag to force a rebuild without a pin change.
# SHVR_ARCH is folded in so the two arches occupy disjoint OID namespaces even
# though their recipe files are byte-identical (the arch is selected by env var,
# not by editing a recipe) — without this the content-addressed skip would treat
# an amd64 and an arm64 build of the same target as interchangeable.
shvr_toolchain_fingerprint ()
{
	dockerfile="${SHVR_DIR_SELF}/Dockerfile"
	fp_rust="$(grep -m1 'ARG RUST_TOOLCHAIN=' "$dockerfile" | sed 's/.*=//')"
	fp_snap="$(grep -m1 'ARG DEBIAN_SNAPSHOT=' "$dockerfile" | sed 's/.*=//')"
	fp_tbase="$(grep -m1 'ARG TOOLCHAIN_BASE=' "$dockerfile" | sed 's/.*=//')"
	fp_rustup="$(grep -oE 'rustup-init-[0-9][0-9.]*\.sh' "$dockerfile" | head -n1)"

	{
		printf 'OIDV=3\n'
		printf 'ARCH=%s\n' "${SHVR_ARCH:-amd64}"
		printf 'RUST=%s\n' "$fp_rust"
		printf 'SNAP=%s\n' "$fp_snap"
		printf 'TBASE=%s\n' "$fp_tbase"
		printf 'RUSTUP=%s\n' "$fp_rustup"
	} | sha256sum | cut -d' ' -f1
}

# Print $1 and, transitively, every ${SHVR_DIR_SELF}/... file it references
# (sourced common/*.sh helpers and directly-used files like ksh's getconf
# wrapper), excluding the update-only common/version_sources/. Each file is
# emitted once.
#
# Transitive matters: common/libedit.sh sources common/ncurses.sh, so without
# following that edge an ncurses.sh edit would leave dash's and osh's OIDs
# unchanged and CI would skip rebuilding them.
shvr_recipe_closure ()
{
	rc_nl='
'
	rc_queue="$1"
	rc_seen=""

	while test -n "$rc_queue"
	do
		rc_file="${rc_queue%%${rc_nl}*}"
		case "$rc_queue" in
		*"${rc_nl}"*) rc_queue="${rc_queue#*${rc_nl}}" ;;
		*)            rc_queue="" ;;
		esac

		case "${rc_nl}${rc_seen}" in
		*"${rc_nl}${rc_file}${rc_nl}"*) continue ;;
		esac
		rc_seen="${rc_seen}${rc_file}${rc_nl}"

		printf '%s\n' "$rc_file"

		rc_refs="$(grep -oE '\$\{SHVR_DIR_SELF\}/[A-Za-z0-9_./-]+' "$rc_file" |
			sed "s#\\\${SHVR_DIR_SELF}#${SHVR_DIR_SELF}#" |
			grep -v '/common/version_sources/' || true)"

		# Unquoted on purpose: split on whitespace. `set -f` (line 6) is on, so
		# no globbing; no recipe path contains a space.
		# shellcheck disable=SC2086
		for rc_ref in $rc_refs
		do
			if test -f "$rc_ref"
			then rc_queue="${rc_queue}${rc_ref}${rc_nl}"
			fi
		done
	done
}

# List the files that define how <shell>_<version> is built: its variant, the
# transitive closure of the ${SHVR_DIR_SELF}/... files that variant references,
# and the patches selected for this version. Folded into the build identity so a
# recipe edit changes the OID and forces a rebuild — turning a forgotten checksum
# regeneration into a loud verify failure instead of a silent skip. Paths are
# emitted absolute; callers hash content under relative names.
#
# Only the *selected* patches are listed, never the whole set: hashing
# patches/<set>/series wholesale would move every yash target's OID whenever any
# yash selector changed, whereas hashing the resolved list keeps each version
# isolated and still catches every meaningful edit (a version added to a selector
# grows that version's list; an edited body changes content; a rename changes the
# name line shvr_build_identity emits).
shvr_recipe_files ()
{
	shell="$1"
	version="$2"
	variant="${SHVR_DIR_SELF}/variants/${shell}.sh"

	if test -f "$variant"
	then shvr_recipe_closure "$variant"
	fi

	# ash and hush share the busybox source tree, hence one patch set.
	shvr_patch_list "$(shvr_patchset "$shell")" "$version"
}

# Build identity (OID) for one target: a hash of the toolchain fingerprint, the
# target's recipe files (variant + sourced helpers + patches), and its committed
# build checksums. The recipe makes a recipe edit change the OID even if the
# committed checksum was not regenerated (so the target rebuilds and the verify
# fails loudly instead of being silently skipped); the committed checksums are
# the authoritative intended output. Recipe file contents are hashed under their
# SHVR_DIR_SELF-relative names so the OID is machine-independent. Prints MISSING
# (and warns) when no committed checksums exist, so such a target is always
# (re)built. Pass a precomputed fingerprint as $2 to avoid recomputing it.
shvr_build_identity ()
{
	target="$1"
	fingerprint="${2:-$(shvr_toolchain_fingerprint)}"
	dir="$(shvr_build_checksums_dir)/${target}"

	if ! test -d "$dir"
	then
		echo "shvr_build_identity: no build checksums for ${target} at ${dir}" >&2
		echo MISSING
		return 0
	fi

	bi_shell="${target%%_*}"
	bi_version="${target#*_}"

	{
		printf '%s\n' "$fingerprint"
		shvr_recipe_files "$bi_shell" "$bi_version" | LC_ALL=C sort | while IFS= read -r f
		do
			printf 'F %s\n' "${f#${SHVR_DIR_SELF}/}"
			cat "$f"
		done
		find "$dir" -name '*.sha256sums' | LC_ALL=C sort | while IFS= read -r f
		do cat "$f"
		done
	} | sha256sum | cut -d' ' -f1
}

# Emit "<target> <oid>" for every target (or the targets passed as arguments).
shvr_build_identities ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_buildset))
	fi
	fingerprint="$(shvr_toolchain_fingerprint)"
	for bi_target in "$@"
	do
		printf '%s %s\n' "$bi_target" "$(shvr_build_identity "$bi_target" "$fingerprint")"
	done
}

# Print a dynamic GitHub Actions matrix (JSON) of the targets that need work for
# the current SHVR_ARCH (default amd64). Reads
# "<target> <arch> <current-oid> [<promotable>]" lines from <registry_oid_file>
# (the OID currently published for each target+arch, or MISSING/FORCE), compares
# against the freshly computed desired OID for this arch, and includes any target
# that is missing, forced, or mismatched. Each emitted row carries "arch" so the
# workflow can route it to the matching native runner. Run once per arch (set
# SHVR_ARCH); the fingerprint and checksum dir are arch-specific, so the desired
# OID and the skip decision are independent per arch. Does no network I/O: the
# registry read happens in the workflow and is passed in as a file.
#
# <mode> selects which half of the work is emitted, and the two are disjoint:
#
#   build    (default) targets that must actually be compiled
#   promote  targets whose exact OID is ALREADY published, under the
#            content-addressed oid-<arch>-<oid> tag, and so only need re-tagging
#
# The promotable flag is the optional 4th column, decided by the caller (it takes
# a registry lookup, and this function does no I/O). Absent or anything but "yes"
# means build, so a 3-column file behaves exactly as before.
shvr_plan_matrix ()
(
	registry_file="$1"
	mode="${2:-build}"
	arch="${SHVR_ARCH:-amd64}"
	fingerprint="$(shvr_toolchain_fingerprint)"

	# Slurp to a real file so it is re-readable per target (handles /dev/stdin).
	reg="${TMPDIR:-/tmp}/shvr_plan.$$"
	trap 'rm -f "$reg"' EXIT INT TERM
	cat "$registry_file" > "$reg"

	printf '{"include":['
	first=1
	for target in $(shvr_buildset)
	do
		desired="$(shvr_build_identity "$target" "$fingerprint")"
		current="$(awk -v t="$target" -v a="$arch" '$1 == t && $2 == a {print $3; exit}' "$reg")"
		promotable="$(awk -v t="$target" -v a="$arch" '$1 == t && $2 == a {print $4; exit}' "$reg")"

		# Skip only when the published OID matches and is a real identity.
		if test "$desired" != MISSING && test "x$current" = "x$desired"
		then continue
		fi

		# Everything past here needs work; the only question is which kind. A row
		# whose exact OID is already published is re-tagged, not rebuilt. Rows are
		# assigned to exactly one mode, so build and promote never overlap and
		# every target needing work lands in one of them.
		row_mode=build
		if test "x$promotable" = xyes
		then row_mode=promote
		fi
		if test "x$row_mode" != "x$mode"
		then continue
		fi

		shvr_clear_versioninfo
		interpreter="${target%%_*}"
		version="${target#*_}"
		. "${SHVR_DIR_SELF}/variants/${interpreter}.sh"
		"shvr_versioninfo_${interpreter}" "$version"
		cache_path="${build_srcdir#${SHVR_DIR_SRC}/}"

		if test "$first" = 1
		then first=0
		else printf ','
		fi
		printf '{"target":"%s","arch":"%s","shell":"%s","version":"%s","cache_path":"%s","oid":"%s"}' \
			"$target" "$arch" "$interpreter" "$version" "$cache_path" "$desired"
	done
	printf ']}\n'
)

shvr "${@:-}"