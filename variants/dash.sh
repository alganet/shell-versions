#!/usr/bin/env sh

# Copyright (c) Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

shvr_targets_dash ()
{
	shvr_cache targets_dash \
		curl --no-progress-meter "https://git.kernel.org/pub/scm/utils/dash/dash.git/refs/" |
			grep -Eoi "href='[^']*'" |
			sed -n "
				s/^href='\/pub\/scm\/utils\/dash\/dash.git\/snapshot\/dash-/dash_/
				s/'$//
				/^dash_[0-9][0-9]*.*\.tar\.gz$/ {
					s/\.tar\.gz$//
					p
				}
			" |
			grep -v "^dash_0\.5\.[0-6]$" |
			sort -u |
			sort -V -r

	return
	cat <<-@
		dash_0.5.11
		dash_0.5.11.5
		dash_0.5.10.2
		dash_0.5.9.1
		dash_0.5.8
		dash_0.5.7
		dash_0.5.6.1
		dash_0.5.5.1
	@
}

shvr_majors_dash ()
{
	shvr_targets_dash | sed -n 's/^dash_0\.\([0-9]*\).*$/dash_0\.\1/p' | sort -u | sort -r
}

shvr_minors_dash () { shvr_semver_minors dash "$@"; }
shvr_patches_dash () { shvr_semver_patches dash "$@"; }

shvr_build_dash ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/dash/${version}"
	mkdir -p "${build_srcdir}"

	apt-get -y install \
		wget gcc automake autoconf dpkg-dev
	wget -O "${build_srcdir}.tar.gz" \
		"https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-$version.tar.gz"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}"

	cd "${build_srcdir}"

	# TODO remove this dependency
	build_arch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"

	if test -f ./autogen.sh
	then
		./autogen.sh
	else
		aclocal
		autoheader
		automake --add-missing
		autoconf
	fi

	./configure \
		--build="$build_arch" \
		--prefix="${SHVR_DIR_OUT}/dash_$version"

	make -j "$(nproc)"
	mkdir -p "${SHVR_DIR_OUT}/dash_${version}/bin"
	cp "src/dash" "${SHVR_DIR_OUT}/dash_$version/bin"
	
	"${SHVR_DIR_OUT}/dash_${version}/bin/dash" -c "echo dash version $version"
}
