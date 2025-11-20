#!/bin/sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# Script intended to be ran from inside the docker container

# Keep compatibility with direct shell execution
if test -f "$1"
then
	exec "$@"
	exit $?
fi

display_run () {
	echo "# $1"
	if test "x$*" = "x$1"
	then set -- "$1" -c ':'
	fi
	"${@:-}"
}

display_compare () {
	if test "$1" = "$COMPARE"
	then return 0
	fi

	OUTPUT="$("$@")"
	if test "x$OUTPUT" = "x$EXPECTED"
	then
		echo "# OK $1"
	else
		echo "# NOT OK $1"
		echo "$OUTPUT"
	fi
}

COMPARE=''
EXPECTED=''
MATCH='*'
ACTION=display_run

while test -n "$1" && test "${1#--}" != "$1"
do
	case "${1:-}" in
		--help)
			echo "Usage: entrypoint.sh [--match <shell-name>] [--compare <reference-shell>] <commands>"
			echo
			echo "Examples:"
			echo "  # List all shells"
			echo "    entrypoint.sh"
			echo "  # Run a command in all shells matching 'ash*'"
			echo "    entrypoint.sh --match 'ash*' -c 'echo Hello World'"
			echo "  # Compare output of a command against a reference shell"
			echo "    entrypoint.sh --compare '/opt/bash_5.3/bin/bash' -c 'echo \${BASH_VERSION:-}'"
			exit 0
			;;
		--match)
			if ! test -n "$2" || test "${2#--}" != "$2"
			then
				echo "Error: --match requires an argument" >&2
				exit 1
			fi
			MATCH="$2"
			shift 2
			;;
		--compare)
			if ! test -n "$2" || test "${2#--}" != "$2"
			then
				echo "Error: --match requires an argument" >&2
				exit 1
			fi
			ACTION=display_compare
			COMPARE="$2"
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			echo "Unknown option: $1" >&2
			exit 1
			;;
	esac
done

if test -n "$COMPARE"
then
	if ! test -x "$COMPARE"
	then
		echo "Error: reference shell '$COMPARE' is not executable" >&2
		exit 1
	fi
	echo "--- REFERENCE ---"
	echo "# $COMPARE"
	EXPECTED="$("$COMPARE" "$@")"
	echo "$EXPECTED"
	echo "--- TESTS ---"
fi

RAN_SOMETHING=0
while read -r sh_path || test -n "$sh_path"
do
	if test "$MATCH" != '*'
	then
		sh_name="${sh_path#'/opt/'}"
		sh_name="${sh_name%'/bin'*}"
		eval "
			case \$sh_name in
				$MATCH) : ;;
				*) continue ;;
			esac
		"
	fi

	$ACTION "$sh_path" "$@"
	RAN_SOMETHING=1

done < /opt/shvr/manifest.txt

if test "$RAN_SOMETHING" = 0
then
	echo "Error: no shells matched '$MATCH'" >&2
	exit 1
fi