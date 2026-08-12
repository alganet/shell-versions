#!/bin/sh

# SPDX-FileCopyrightText: 2026 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# Retry a command with backoff.
#
#   sh .github/retry.sh <attempts> <base-delay-seconds> <command> [args...]
#
# Wraps the SOURCE-DOWNLOAD steps, which are the pipeline's most failure-prone
# work and its least recoverable: common-sources and toolchain are single jobs
# that every build job depends on, so one bad minute at ftp.gnu.org, sourceforge
# or thrysoee.dk fails the whole run before a single shell is compiled.
#
# curl already retries inside shvr_fetch, and shvr_fetch_mirrors already tries
# other hosts where a source has them. This is the outer layer for what neither
# covers: a host that is down for longer than curl's retry budget, a source with
# no mirror worth naming, and the case where several unrelated upstreams are
# unhappy at once. Retrying the whole download command is cheap because it is
# resumable -- shvr_fetch skips anything already present and verified, so attempt
# 2 only re-fetches what attempt 1 did not finish.
#
# Delay grows linearly (base, 2*base, ...) rather than staying flat: a rate-limited
# host needs more room than a blipping one, and a flat delay just re-hits it.

set -eu

attempts="$1"
base_delay="$2"
shift 2

attempt=1
while :
do
	if "$@"
	then
		if test "$attempt" -gt 1
		then
			echo "::warning::retry.sh: '$*' succeeded on attempt ${attempt}/${attempts}; an upstream is flaky"
		fi
		exit 0
	fi

	if test "$attempt" -ge "$attempts"
	then
		echo "::error::retry.sh: '$*' failed ${attempts} time(s); see the log above for the failing URL"
		exit 1
	fi

	delay=$((base_delay * attempt))
	echo "retry.sh: attempt ${attempt}/${attempts} of '$*' failed; retrying in ${delay}s" >&2
	sleep "$delay"
	attempt=$((attempt + 1))
done
