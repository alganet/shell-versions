# alganet/shell-versions

[![Docker Build](https://github.com/alganet/shell-versions/actions/workflows/docker.yml/badge.svg?branch=main)](https://github.com/alganet/shell-versions/actions/workflows/docker.yml)

Multiple versions of multiple shells.

## Multiple Shell Image (~40MB)

 - [multi](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=multi-) - The latest supported version of each supported shell

```sh
$ docker run -it --rm alganet/shell-versions find /opt -type f
/opt/posh_0.14.1/bin/posh
/opt/dash_0.5.11/bin/dash
/opt/yash_2.53/bin/yash
/opt/zsh_5.9/bin/zsh
/opt/osh_0.14.0/bin/osh
/opt/busybox_1.36.0/bin/busybox
/opt/loksh_7.2/bin/loksh
/opt/ksh_93u+m-v1.0.4/bin/ksh
/opt/ksh_93u+m-v1.0.4/bin/shcomp
/opt/bash_5.2.15/bin/bash
/opt/oksh_7.2/bin/oksh
/opt/mksh_R59c/bin/mksh

$ docker run -it --rm alganet/shell-versions /opt/bash_5.2.15/bin/bash -c "echo hello there"
hello there
```

## Single Shell Images (~30MB each)

 - [bash](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=bash-)
 - [busybox](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=busybox-) - Only the `ash` and `hush` applets and their dependencies are built.
 - [dash](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=dash-)
 - [gwsh](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=gwsh-)
 - [ksh](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=ksh-) - `shcomp` is also available.
 - [loksh](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=loksh-)
 - [mksh](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=mksh-)
 - [oksh](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=oksh-)
 - [osh](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=osh-)
 - [posh](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=posh-)
 - [yash](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=yash-)
 - [zsh](https://hub.docker.com/r/alganet/shell-versions/tags?page=1&ordering=name&name=zsh-)

Check out the [full list of tags](https://hub.docker.com/r/alganet/shell-versions/tags).


## Building Locally

```sh
$ docker build -t "mydash" --build-arg TARGETS="dash_0.5.12" .
$ docker run -it --rm mydash ls /opt
```

You can pass multiple targets separated by space, see a list of possible ones on the `.github/workflows/docker.yml` file.

Each script on the `variants` folder should be able to handle new versions of each shell as they come out.