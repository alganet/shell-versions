[#]:: (SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>)
[#]:: (SPDX-License-Identifier: ISC)

# alganet/shell-versions

<!-- [![Docker Build](https://github.com/alganet/shell-versions/actions/workflows/docker.yml/badge.svg?branch=main)](https://github.com/alganet/shell-versions/actions/workflows/docker.yml) -->

Multiple versions of multiple shells. Ideal for testing portable shell scripts.

## Images

 - **latest** - Contains the two most recent released versions of each shell. Ideal for testing up to date scripts. Never contains pre-releases.
 - **all** - Everything we can build in a single image, including each shell's newest pre-release where upstream publishes one. Ideal for testing legacy and backwards compatible scripts, and for catching breakage before an upstream release ships.

### Pre-releases

Shells whose upstream publishes an alpha/beta/rc/test build contribute their
**newest** such build to `all` (only the newest — we do not archive the whole
pre-release history). They are named by their upstream token, so they sort and
read as what they are:

```sh
$ docker run -it --rm alganet/shell-versions:all /opt/bash_5.3-rc2/bin/bash --version
```

A pre-release is kept as long as it is the newest one upstream offers, even when
a newer *released* version already exists — it is the last pre-release that shell
had. It rolls forward on its own when upstream publishes a newer one, and
disappears if upstream withdraws it. Pre-releases never enter `latest`.

Shells are built on debian-slim, and copied during multi-stage to a barebones
busybox image (you get busybox tools + all shells).

Both images are **multi-arch manifest lists** covering `linux/amd64` and
`linux/arm64`, so `docker pull` selects the right architecture automatically —
on Apple Silicon macOS you get native `arm64` binaries with no Rosetta/QEMU
emulation. The same `<shell>_<version>` set is published for every architecture.

Every individual shell is published as its own multi-arch tag too, so you can
pull a single shell instead of the whole image and still get your native arch.
A per-version tag *is* that shell — it runs directly, and its arguments are the
shell's own:

```sh
$ docker run -it --rm alganet/shell-versions:bash_5.3.15
bash-5.3$ echo "$BASH_VERSION"
5.3.15(1)-release

$ docker run --rm alganet/shell-versions:dash_0.5.12 -c 'echo Hello World'
Hello World
```

These images are built on the same busybox userland as `latest` and `all`, so
scripts that reach for `grep`, `sed` or `ls` still work, and
`--entrypoint /bin/sh` is there when you want to look around. The shell is also
on `PATH` under its own name. The multi-shell helpers below do not apply to a
single-shell image; `-e SHVR_ENTRYPOINT=multi` brings them back if you want them.

### Checksums

Every image carries the sha256 of the binaries it contains, and only those:

```sh
$ docker run --rm --entrypoint /bin/sh alganet/shell-versions:bash_5.3.15 \
    -c 'cat /opt/shvr/checksums/build/*/bash_5.3.15/bin/bash.sha256sums'
```

The same holds for `latest` and `all` — each attests to exactly the shells inside
it, under `/opt/shvr/checksums/build/<arch>/<shell>_<version>/`.

### Building Your Own Collection

Per-version tags are ordinary `COPY --from` sources, so you can assemble a set
containing only the shells you care about:

```dockerfile
FROM busybox:stable-musl
COPY --from=alganet/shell-versions:bash_5.3.15 /opt /opt
COPY --from=alganet/shell-versions:dash_0.5.12 /opt /opt
COPY --from=alganet/shell-versions:zsh_5.9.2   /opt /opt
RUN find /opt \( -type l -o -type f \) -not -path '*/shvr/*' | sort > /opt/shvr/manifest.txt
ENTRYPOINT [ "/bin/sh", "/opt/shvr/entrypoint.sh" ]
```

The `find` regenerates the manifest the entrypoint reads, so the resulting image
gets the multi-shell helpers described below.

## Basic Usage

List all shells:

```sh
$ docker run -it --rm alganet/shell-versions
```

Run a shell individually:

```sh
$ docker run -it --rm alganet/shell-versions /opt/bash_5.3/bin/bash -c 'echo Hello World'
```

## Advanced Usage

shell-versions docker entrypoint provides helpers to perform tasks on several shells
at once. The `--help` option shows some examples:

```sh
$ docker run -it --rm alganet/shell-versions --help
Usage: entrypoint.sh [--match <shell-name>] [--compare <reference-shell>] <commands>

Examples:
  # List all shells
    entrypoint.sh
  # Run a command in all shells matching 'ash*'
    entrypoint.sh --match 'ash*' -c 'echo Hello World'
  # Compare output of a command against a reference shell
    entrypoint.sh --compare '/opt/bash_5.3/bin/bash' -c 'echo ${BASH_VERSION:-}'
```

### Using a Custom List

You can select which shells will be used by the entrypoint by overriding the
`/opt/shvr/manifest.txt` file inside the container. By default, the file contains
all the shells built.

First, create a `manifest.txt` file locally, containing the paths you want:

```
/opt/bash_5.3/bin/bash
/opt/ash_1.37.0/bin/ash
```

Then, mount it and run it:

```sh
$ docker run -it --rm -v${PWD}/manifest.txt:/opt/shvr/manifest.txt alganet/shell-versions
# /opt/bash_5.3/bin/bash
# /opt/ash_1.37.0/bin/ash
```

Any options you use (`--match`, `--compare`, etc) will be then applicable only to the
shells you selected.

## Building Locally

You can build shell-versions locally.

```sh
$ sh shvr.sh download $(sh shvr.sh targets)
$ docker build -t "mymultishell" --build-arg TARGETS="$(sh shvr.sh targets)" .
$ docker run -it --rm "mymultishell"
```

You can pass a shorter list of versions instead of the full `$(sh shvr.sh targets)`.

The build follows `--platform`: it reads BuildKit's `TARGETARCH`, so the musl
and Rust cross-targets always match the platform you ask for. To build for
`linux/arm64` (the native architecture on Apple Silicon), just pass the
platform — there is no separate arch flag to keep in sync:

```sh
$ docker buildx build --platform linux/arm64 \
    -t "mymultishell" --build-arg TARGETS="$(sh shvr.sh targets)" .
```

Omitting `--platform` builds for the host architecture.

This is particularly useful if you want to test a version that we don't bundle
by default, such as an old patch. Our scripts are able to build most
intermediate versions without modifications, but we can't include them all in
any of the default images.

## Updating the Version Lists

The supported versions live in `versions/<shell>.{all,current}` (plus an optional
`versions/<shell>.excluded` denylist). To pull in new upstream releases, run
`sh shvr.sh update [<shell>]` (with no argument it updates every shell), which
refreshes `versions/<shell>.all` from each shell's upstream source. Probe any
newly-discovered versions before shipping them; if one fails to build with the
current toolchain, add it to `versions/<shell>.excluded` (with a comment recording
the failure) and re-run the update to drop it. An exclusion line is just the
version (`5.3.1`), optionally followed by the architecture it fails on
(`5.3.1 arm64`) — the version is dropped from every architecture either way (the
published lists stay identical across architectures), and the arch tag documents
where it failed so it can be re-enabled once fixed. Finally, run
`sh shvr.sh github_regen_all` to regenerate the `.github/` build matrix from the
data files, and commit `versions/` and `.github/` together.
