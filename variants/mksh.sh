#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_mksh ()
{
	shvr_cache targets_mksh \
		curl --no-progress-meter "http://www.mirbsd.org/MirOS/dist/mir/mksh/" |
			grep -Eoi 'HREF="[^"]*"' |
			sed -n '
				s/^HREF="mksh-/mksh_/
				s/"$//
				/^mksh_R[0-9][0-9]*.*\.tgz$/ {
					s/\.tgz$//
					p
				}
			' |
			grep -v "^mksh_R4[234].*$" |
			sort -u |
			sort -V -r
}

shvr_majors_mksh ()
{
	shvr_targets_mksh | sed -n 's/^mksh_R\([0-9]*\).*$/mksh_R\1/p' | grep -v '_R41' | sort -u | sort -r
}

shvr_minors_mksh ()
{
	shvr_targets_mksh | sed -n 's/^\('$1'\)\(.*\)$/\1/p' | sort -u | sort -r
}

shvr_patches_mksh ()
{
	shvr_targets_mksh | sed -n 's/^\('$1'\)\(.*\)$/\1\2/p' | sort -u | sort -r
}

shvr_build_mksh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/mksh/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc make
	wget -O "${build_srcdir}.tgz" \
		"http://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-$version.tgz"

	tar --extract \
		--file="${build_srcdir}.tgz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	sh ./Build.sh

	mkdir -p "${SHVR_DIR_OUT}/mksh_${version}/bin"
	cp "mksh" "${SHVR_DIR_OUT}/mksh_$version/bin"
	
	"${SHVR_DIR_OUT}/mksh_${version}/bin/mksh" -c "echo mksh version $version"
}
