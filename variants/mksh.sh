#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_mksh ()
{
	cat <<-@
		mksh_R59c
		mksh_R58
		mksh_R57
		mksh_R56c
		mksh_R55
		mksh_R54
		mksh_R53a
		mksh_R52c
		mksh_R51
		mksh_R50f
		mksh_R49
		mksh_R48b
		mksh_R47
		mksh_R46
		mksh_R45
	@
}

shvr_majors_mksh ()
{
	shvr_targets_mksh | sed -n 's/^mksh_R\([0-9]*\).*$/mksh_R\1/p' | uniq
}

shvr_minors_mksh ()
{
	shvr_targets_mksh | sed -n 's/^\('$1'\)\(.*\)$/\1/p' | uniq
}

shvr_patches_mksh ()
{
	shvr_targets_mksh | sed -n 's/^\('$1'\)\(.*\)$/\1\2/p' | uniq
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
