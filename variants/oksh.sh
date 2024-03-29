#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_oksh ()
{
	shvr_cache targets_oksh \
		curl --no-progress-meter https://api.github.com/repos/ibara/oksh/releases |
			sed -n '
				/^    "tag_name": "/ {
					s/^    "tag_name": "oksh-/oksh_/
					s/",$//
					p
				}
			' |
			grep -v "^oksh_[5]\.[0-9]$" |
			grep -v "^oksh_[6]\.7\.[0-4]$" |
			sort -u |
			sort -V -r
	return
	cat <<-@
		oksh_7.2
		oksh_7.1
		oksh_7.0
		oksh_6.9
		oksh_6.8.1
		oksh_6.7.1
		oksh_6.6
		oksh_6.5
	@
}

shvr_majors_oksh () { shvr_semver_majors oksh; }
shvr_minors_oksh () { shvr_semver_minors oksh "$@"; }
shvr_patches_oksh () { shvr_semver_patches oksh "$@"; }

shvr_build_oksh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/oksh/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc make
	wget -O "${build_srcdir}.tar.xz" \
		"https://github.com/ibara/oksh/releases/download/oksh-$version/oksh-$version.tar.gz"

	tar --extract \
		--file="${build_srcdir}.tar.xz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	./configure \
		--prefix="${SHVR_DIR_OUT}/oksh_$version"

	make -j "$(nproc)"
	mkdir -p "${SHVR_DIR_OUT}/oksh_${version}/bin"
	cp "oksh" "${SHVR_DIR_OUT}/oksh_$version/bin"
	
	"${SHVR_DIR_OUT}/oksh_${version}/bin/oksh" -c "echo oksh version $version"
}
