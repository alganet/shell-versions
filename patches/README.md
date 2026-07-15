# patches

Source patches, one flat directory per patch set, quilt style.

```
patches/<set>/
├── series          which patch applies to which versions
└── *.diff          the patches
```

Everything here is applied with `patch -p0` from the root of the extracted
source tree. Nothing else is needed to use these — no shvr, no container, no
build system. That is the point: if you want to reproduce one of our trees, or
lift a fix into your own build, the patch and the version list are all there is.

## series

```
# <patch-file>  <version> [<version> ...]

arith-c-include-wctype.diff \
	2.10 2.11 2.12 2.13 2.14 2.15 2.16 2.17 2.18 2.19 \
	...
	2.40 2.41 2.42 2.43 2.44

common-h-has-builtin-guard.diff  2.61
```

A patch applies to a version when the version's token matches one of the
patterns on its line. Patterns are ordinary shell globs matched against the
exact token (`1.0.*-uplusm` works), but they are written out as explicit lists so
they can be checked line by line against `versions/<set>.all`.

Line order is apply order. There are no `NNN-` filename prefixes.

There is deliberately **no version-range syntax and no version comparator**.
Every band here is closed and historical — busybox 1.8.3..1.18.5, mksh
R40f..R44, yash 2.10..2.44 — so a range would buy nothing but the chance of
silently widening onto a version that must stay byte-identical to its committed
build checksum. The 1.2.x busybox island is the live example: it carries the same
`platform.h` text as the band above it, it would happily accept the patch, and it
must not get it.

## Doing it by hand

```sh
sh shvr.sh patches yash_2.30
#   patches/yash/arith-c-include-wctype.diff

tar xf yash-2.30.tar.xz && cd yash-2.30
patch -p0 < ../patches/yash/arith-c-include-wctype.diff
```

## Patch headers

Each diff carries a [DEP-3][dep3] header — what it fixes and why, and whether
upstream took it. `patch(1)` ignores everything before the first `---` line.

A `Reproducibility:` field marks the patches that exist to pin nondeterminism
rather than to fix a build: an `iffe` probe that times `mmap`, a `conf.tab` probe
that reads the build host's `/proc/sys/kernel/pid_max`, uninitialised long-double
padding that leaks into a generated header. Those are load-bearing. Removing one
does not break the build; it breaks the checksums, later, on someone else's
machine.

The version list lives in `series` and only in `series` — never repeat it in a
header, where it would go stale.

[dep3]: https://dep-team.pages.debian.net/deps/dep3/

## Sets, not shells

A set is named after the *source* it patches, which is not always the shell.
`ash` and `hush` are both built from one busybox tree, so both draw from
`patches/busybox/` (see `shvr_patchset` in `common/patches.sh`). This is also why
`versions/busybox.all`, not a per-shell list, is what a busybox selector is
checked against.

## Not patches

Files that get copied over something wholesale live in
[`../payloads`](../payloads) instead. If nothing of the original survives, a diff
is just noise.

`bash` additionally downloads the *upstream* GNU patches (`bash52-001` and
friends) at build time and applies them separately — see `shvr_download_bash`.
Those are not stored here. `patches/bash/` holds only ours.

## Checking

```sh
sh shvr.sh check_patches
```

Catches a series entry naming a patch that does not exist, a `.diff` nobody
references, and — the one that actually bites — a selector matching no known
version.

Patches are folded into each target's build identity, so editing one changes its
OID and forces a rebuild, which then verifies against the committed build
checksums. If you change what a patch does, expect that verify to fail; that is
the mechanism working.
