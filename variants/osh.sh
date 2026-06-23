#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"
. "${SHVR_DIR_SELF}/common/readline.sh"

shvr_static_osh ()
{
	return 0
}

shvr_current_osh ()
{
	shvr_read_versions osh current
}

shvr_targets_osh ()
{
	shvr_read_versions osh all
}

shvr_update_osh ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/html_listing.sh"
	shvr_versions_from_html_listing \
		"https://www.oils.pub/release/" \
		'([0-9]+\.[0-9]+\.[0-9]+)/' |
		shvr_merge_versions osh
}

shvr_versioninfo_osh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/osh/${version}"
}

shvr_download_osh ()
{
	shvr_versioninfo_osh "$1"

	mkdir -p "${SHVR_DIR_SRC}/osh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://oils.pub/download/oils-for-unix-${version}.tar.gz" "${build_srcdir}.tar.gz"
	fi

	# osh links GNU readline for interactive line editing/history/completion.
	shvr_download_readline
}

shvr_build_osh ()
{
	shvr_versioninfo_osh "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	# Build static GNU readline (against the in-tree ncurses) so osh gets line
	# editing, history and completion. Its libreadline.a is self-contained
	# (termcap merged in), which matters because osh probes and links a bare
	# `-lreadline` with no `-lncurses`. NOTE: GNU readline is GPLv3, so the osh
	# binary is a GPL combined work (Oils itself is Apache-2.0). osh has no
	# non-GPL editor: libedit's readline-compat is missing functions Oils calls.
	shvr_build_readline
	cd "${build_srcdir}"

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export CXXFLAGS="-frandom-seed=1"
	export LDFLAGS="-static -Wl,--build-id=none"

	# Oils uses 'c++' as its default compiler and builds output paths from
	# the --cxx value, so we provide a wrapper that invokes the musl
	# cross-compiler with static flags (older oils versions ignore LDFLAGS)
	mkdir -p "${build_srcdir}/.musl-bin"
	cat > "${build_srcdir}/.musl-bin/c++" <<-WRAPPER
		#!/bin/sh
		exec "$(shvr_musl_cxx)" -static -Wl,--build-id=none "\$@"
	WRAPPER
	chmod +x "${build_srcdir}/.musl-bin/c++"
	# configure's feature probes (cc_quiet) default to 'cc'; without a musl 'cc'
	# they would use the host gcc/glibc, which cannot link our musl static
	# libreadline.a, so readline detection silently fails and osh builds without
	# it. Provide a musl 'cc' wrapper so probes match the actual (musl) build.
	cat > "${build_srcdir}/.musl-bin/cc" <<-WRAPPER
		#!/bin/sh
		exec "$(shvr_musl_cc)" -static -Wl,--build-id=none "\$@"
	WRAPPER
	chmod +x "${build_srcdir}/.musl-bin/cc"
	export PATH="${build_srcdir}/.musl-bin:$PATH"

	./configure \
		--readline "$(shvr_readline_prefix)" \
		--prefix="${SHVR_DIR_OUT}/osh_$version"

	_build/oils.sh

	unset SOURCE_DATE_EPOCH TZ CXXFLAGS LDFLAGS
	export PATH="${PATH#*:}"

	mkdir -p "${SHVR_DIR_OUT}/osh_${version}/bin"
	cp "_bin/cxx-opt-sh/oils-for-unix" "${SHVR_DIR_OUT}/osh_$version/bin/osh"

	# Strip binary to ensure reproducible output
	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/osh_${version}/bin/osh"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/osh_${version}/bin/osh"
	chmod 755 "${SHVR_DIR_OUT}/osh_${version}/bin/osh"

	"${SHVR_DIR_OUT}/osh_${version}/bin/osh" -c "echo osh version $version"
}

shvr_deps_osh ()
{
	shvr_versioninfo_osh "$1"
	apt-get -y install \
		curl make
}
