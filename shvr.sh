#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

set -euf

SHVR_DIR_SELF="$(cd "$(dirname "$0")"; pwd)"
SHVR_DIR_SRC="${SHVR_DIR_SRC:-"/usr/src/shvr"}"
SHVR_DIR_OUT="${SHVR_DIR_OUT:-"/opt"}"
SHVR_DIR_CACHE="${SHVR_DIR_CACHE:-"${SHVR_DIR_SELF}/.cache"}"

shvr ()
{
	shvr_"${@:-}"
}

shvr_build ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_targets))
	fi

	set -x

	shvr_each build "${@:-}"
}

shvr_targets ()
{
	if test -z "$*"
	then set -- $(printf '%s ' $(shvr_interpreters))
	fi

	shvr_each targets "${@:-}"
}

shvr_semver_majors ()
{
	"shvr_targets_$1" | cut -d'.' -f1 | uniq | sed 's/^'"$1"'_/'"$1"'_/'
}

shvr_semver_minors ()
{
	"shvr_targets_$1" | sed -n 's/^\('"$2"'\)\([.][0-9]*\)\([.]*.*\)/\1\2/p' | uniq
}

shvr_semver_patches ()
{
	"shvr_targets_$1" | sed -n 's/^\('"$2"'\)\([.][0-9]*\)\([.]*[0-9]*\)/\1\2/p' | uniq
}

shvr_versions ()
{
	if test $# = 0
	then set -- $(shvr_interpreters | tr '\n' ' ')
	fi

	while test $# -gt 0
	do
		. "${SHVR_DIR_SELF}/variants/${1}.sh"
		majors="$(shvr_majors_$1 | head -n ${SHVR_MAJORS:-16} | tr '\n' ' ')"
		if test -n "$majors"
		then printf '%s ' "$1-latest"
		fi
		for major in $majors
		do
			minors="$(shvr_minors_$1 $major | head -n ${SHVR_MINORS:-16} | tr '\n' ' ')"
			printf '%s ' "$major-latest"
			if test -z "$minors"
			then echo "$major"
			fi
			for minor in $minors
			do
				patches="$(shvr_patches_$1 $minor | sort -V -r | head -n ${SHVR_PATCHES:-1} | tr '\n' ' ')"
				if test "$major " != "$minors" && test "$minor " != "$patches"
				then printf '%s ' "$minor-latest"
				fi
				if test -z "$patches"
				then
					echo "$minor"
				fi
				for patch in $patches
				do
					echo "$patch"
				done
			done
		done
		shift
	done
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
		interpreter="${1%%_*}"
		version="${1#*_}"

		. "${SHVR_DIR_SELF}/variants/${interpreter}.sh"

		"shvr_${subcommand}_${interpreter}" "$version"
		rm -Rf "${SHVR_DIR_SRC}/${interpreter}"
		shift
	done
}

shvr_yml_tags ()
{
	interpreter="${1%%_*}"
	version="${1#"$interpreter"_}"
	shvr_versions "$interpreter" |
		sed -n '/'"$(echo "$version" |
		sed 's/\./\\./g')"'$/p' |
		tr ' ' '\n' |
		sed 's/^/alganet\/shell-versions:/'
}

shvr_yml_generate_workflows ()
{
	shvr_yml_header pull_request "Docker Build Pipeline" "false" > ".github/workflows/docker-build.yml"
	shvr_yml_items single >> ".github/workflows/docker-build.yml"

	shvr_yml_header push "Docker Push Pipeline" "true" > ".github/workflows/docker-push.yml"
	shvr_yml_items multi >> ".github/workflows/docker-push.yml"
}

shvr_yml_header ()
{
	cat <<-@
		# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
		# SPDX-License-Identifier: ISC

		# THIS FILE IS AUTO-GENERATED, DO NOT EDIT

		name: $2

		on:
		  $1:
		    branches:
		      - "main"
		jobs:
		  build:
		    runs-on: ubuntu-latest
		    continue-on-error: \${{ matrix.can_fail_build }}
		    steps:
		      - uses: actions/checkout@v3

		      - name: Log in to Docker Hub
		        uses: docker/login-action@v2
		        with:
		          username: \${{ secrets.DOCKER_USER }}
		          password: \${{ secrets.DOCKER_PASS }}

		      - name: Set up Docker Buildx
		        uses: docker/setup-buildx-action@v2

		      - name: "Build Docker Image (push: $3)"
		        uses: docker/build-push-action@v4
		        with:
		          context: .
		          push: $3
		          tags: \${{ matrix.tags }}
		          labels: \${{ matrix.name }}
		          build-args: |
		            TARGETS=\${{ matrix.targets }}

		    strategy:
		      fail-fast: false
		      matrix:
		        include:
	@
}

shvr_latest ()
{
	shvr_versions "$1" | grep latest | sed '/beta\|alpha\|rc/ d'
}

shvr_yml_items ()
{
	if test "$1" = "multi"
	then
		cat <<-@
	          ##########################################
	          #                multi
	          ##########################################
	          #multi-latest
	          - name: multi-latest
	            targets: "$(SHVR_MAJORS=2 SHVR_MINORS=2 SHVR_PATCHES=1 shvr_versions | sed 's/ $//' | rev | cut -d' ' -f1 | rev | sort -V -r | tr '\n' ' ' )"
	            can_fail_build: false
	            tags: |
	              latest
	              multi-latest
		@
		echo
	fi
	shvr_interpreters | while read -r interpreter
	do
		cat <<-@
	          ##########################################
	          #                $interpreter
	          ##########################################
		@
		if test "$1" = "multi"
		then
			targets="$(shvr_versions "$interpreter" | sed 's/ $//' | rev | cut -d' ' -f1 | rev | sort -V -r | tr '\n' ' ' )"
			if test -n "$targets"
			then
				cat <<-@
				          # $interpreter-all
				          - name: $interpreter-all
				            targets: "$targets"
				            can_fail_build: false
				            tags: |
				              $interpreter-all
			@
			fi
			echo
		fi

		targets="$(shvr_versions "$interpreter")"

		echo "$targets" | while read -r target
		do
			if test -z "$target"
			then continue
			fi
			cat <<-@
		          # $target
		          - name: ${target##* }
		            targets: "${target##* }"
		            can_fail_build: false
		            tags: |$(echo; shvr_yml_tags ${target##* } | sed 's/^/              /')
			@
			echo
		done
		if test -z "${targets:-}"
		then
			cat <<-@

		          # no buildable targets

			@
		fi
	done
}

shvr_cache ()
{
	cache_key="${SHVR_DIR_CACHE}/$1"
	shift

	if ! test -f "$cache_key"
	then
		mkdir -p "${SHVR_DIR_CACHE}"
		"$@" > "$cache_key"
	fi

	cat "$cache_key"
}

shvr "${@:-}"