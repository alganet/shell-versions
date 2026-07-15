#!/bin/sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# Fixed getconf wrapper for reproducible builds.
# ksh's conf.sh uses getconf(1) to discover system limits like ARG_MAX,
# CHILD_MAX, PID_MAX. These are kernel-dependent and vary across CI
# runners, making FEATURE/limits non-deterministic. conf.sh checks
# DEFPATH (/bin:/usr/bin) before PATH, so /usr/bin/getconf must be
# replaced. The original is expected at /usr/bin/getconf.orig.

case "$1" in
ARG_MAX)           echo 2097152 ;;
CHILD_MAX)         echo 15710 ;;
OPEN_MAX)          echo 1024 ;;
PID_MAX)           echo 4194304 ;;
UID_MAX)           echo 60002 ;;
SYSPID_MAX)        echo 2 ;;
CHARCLASS_NAME_MAX) echo 2048 ;;
NL_ARGMAX)         echo 4096 ;;
NL_LANGMAX)        echo 2048 ;;
NL_MSGMAX)         echo 2147483647 ;;
NL_NMAX)           echo 2147483647 ;;
NL_SETMAX)         echo 2147483647 ;;
NL_TEXTMAX)        echo 2147483647 ;;
NSS_BUFLEN_GROUP)  echo 1024 ;;
NSS_BUFLEN_PASSWD) echo 1024 ;;
NZERO)             echo 20 ;;
PATH_MAX)          echo 4096 ;;
PTHREAD_DESTRUCTOR_ITERATIONS) echo 4 ;;
PTHREAD_KEYS_MAX)  echo 1024 ;;
STD_BLK)           echo 1024 ;;
TMP_MAX)           echo 10000 ;;
*)  /usr/bin/getconf.orig "$@" 2>/dev/null || echo "undefined" ;;
esac
