[#]:: (SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>)
[#]:: (SPDX-License-Identifier: ISC)

# alganet/shell-versions

[![Docker Build](https://github.com/alganet/shell-versions/actions/workflows/docker-push.yml/badge.svg?branch=main)](https://github.com/alganet/shell-versions/actions/workflows/docker-push.yml)

Multiple versions of multiple shells. Ideal for testing portable shell scripts.

## Images

 - **latest** - Contains the two most recent versions of each shell. Ideal for testing up to date scripts.
 - **all** - Everything we can build in a single image. Ideal for testing legacy and backwards compatible scripts.

You can list the shells in your image:

```sh
$ docker run -it --rm alganet/shell-versions find /opt -type f
/opt/bash_5.2.15/bin/bash
/opt/dash_0.5.11/bin/dash
...
```

And run them by choosing a version:

```sh
$ docker run -it --rm alganet/shell-versions /opt/bash_5.3/bin/bash -c "echo hello there"
hello there
```

## Building Locally

```sh
$ sh shvr.sh download $(sh shvr.sh targets)
$ docker build -t "mymultishell" --build-arg TARGETS="$(sh shvr.sh targets)" .
$ docker run -it --rm "mymultishell" ls /opt
```

You can pass a shorter list of versions instead of the full `$(sh shvr.sh targets)`.
