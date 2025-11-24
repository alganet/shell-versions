[#]:: (SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>)
[#]:: (SPDX-License-Identifier: ISC)

# alganet/shell-versions

[![Docker Build](https://github.com/alganet/shell-versions/actions/workflows/docker-push.yml/badge.svg?branch=main)](https://github.com/alganet/shell-versions/actions/workflows/docker-push.yml)

Multiple versions of multiple shells. Ideal for testing portable shell scripts.

## Images

 - **latest** - Contains the two most recent versions of each shell. Ideal for testing up to date scripts.
 - **all** - Everything we can build in a single image. Ideal for testing legacy and backwards compatible scripts.

Shells are built on debian-slim, and copied during multi-stage to a barebones
busybox image (you get busybox tools + all shells).

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

This is particularly useful if you want to test a version that we don't bundle
by default, such as an old patch. Our scripts are able to build most
intermediate versions without modifications, but we can't include them all in
any of the default images.
