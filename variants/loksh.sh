#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"

shvr_static_loksh ()
{
	return 0
}

shvr_current_loksh ()
{
	cat <<-@
		loksh_7.8
		loksh_7.7
	@
}

shvr_targets_loksh ()
{
	cat <<-@
		loksh_7.8
		loksh_7.7
		loksh_7.6
		loksh_7.5
		loksh_7.4
		loksh_7.3
		loksh_7.1
		loksh_7.0
		loksh_6.9
		loksh_6.8.1
		loksh_6.7.5
	@
}

shvr_versioninfo_loksh ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/loksh/${version}"
}

shvr_download_loksh ()
{
	shvr_versioninfo_loksh "$1"

	mkdir -p "${SHVR_DIR_SRC}/loksh"

	if ! test -f "${build_srcdir}.tar.xz"
	then
		shvr_fetch "https://github.com/dimkr/loksh/releases/download/$version/loksh-$version.tar.xz" "${build_srcdir}.tar.xz"
	fi
}

shvr_build_loksh ()
{
	shvr_versioninfo_loksh "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.xz" "${build_srcdir}"

	cd "${build_srcdir}"

	# Static musl build with reproducible flags
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC

	# Create meson cross-file for musl static build
	cat > musl-cross.txt <<-EOF
		[binaries]
		c = '$(shvr_musl_cc)'
		ar = '$(shvr_musl_ar)'
		strip = '$(shvr_musl_strip)'

		[built-in options]
		c_args = ['-static', '-frandom-seed=1']
		c_link_args = ['-static', '-Wl,--build-id=none']

		[host_machine]
		system = 'linux'
		cpu_family = 'x86_64'
		cpu = 'x86_64'
		endian = 'little'
	EOF

	meson \
		--prefix="${SHVR_DIR_OUT}/loksh_$version" \
		--cross-file musl-cross.txt \
		build

	ninja -C build

	unset SOURCE_DATE_EPOCH TZ

	mkdir -p "${SHVR_DIR_OUT}/loksh_${version}/bin"
	cp "build/ksh" "${SHVR_DIR_OUT}/loksh_$version/bin/loksh"

	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"
	touch -d "@1" "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"
	chmod 755 "${SHVR_DIR_OUT}/loksh_${version}/bin/loksh"

	"${SHVR_DIR_OUT}/loksh_${version}/bin/loksh" -c "echo loksh version $version"
}

shvr_deps_loksh ()
{
	shvr_versioninfo_loksh "$1"
	apt-get -y install \
		curl meson ninja-build xz-utils
}
