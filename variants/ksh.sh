#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"

shvr_static_ksh ()
{
	shvr_versioninfo_ksh "$1"
	case "$fork_name" in
		*'93uplusm') return 0 ;;
		*)           return 1 ;;
	esac
}

shvr_current_ksh ()
{
	cat <<-@
		ksh_shvrA93uplusm-v1.0.10
		ksh_shvrA93uplusm-v1.0.9
	@
}

shvr_targets_ksh ()
{
	cat <<-@
		ksh_shvrA93uplusm-v1.0.10
		ksh_shvrA93uplusm-v1.0.9
		ksh_shvrA93uplusm-v1.0.8
		ksh_shvrA93uplusm-v1.0.7
		ksh_shvrA93uplusm-v1.0.6
		ksh_shvrA93uplusm-v1.0.4
		ksh_shvrA93uplusm-v1.0.3
		ksh_shvrA93uplusm-v1.0.2
		ksh_shvrA93uplusm-v1.0.1
		ksh_shvrB2020-2020.0.0
		ksh_shvrChistory-b_2016-01-10
		ksh_shvrChistory-b_2012-08-01
		ksh_shvrChistory-b_2011-03-10
		ksh_shvrChistory-b_2010-10-26
		ksh_shvrChistory-b_2010-06-21
		ksh_shvrChistory-b_2008-11-04
		ksh_shvrChistory-b_2008-06-08
		ksh_shvrChistory-b_2008-02-02
		ksh_shvrChistory-b_2007-01-11
	@
}

shvr_versioninfo_ksh ()
{
	version="$1"
	fork_name="${1%%-*}"
	fork_version="${1#*-}"
	build_srcdir="${SHVR_DIR_SRC}/ksh/${version}"
}

shvr_download_ksh ()
{
	shvr_versioninfo_ksh "$1"

	mkdir -p "${SHVR_DIR_SRC}/ksh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		case "$fork_name" in
			*'93uplusm')
				shvr_fetch "https://github.com/ksh93/ksh/archive/refs/tags/${fork_version}.tar.gz" "${build_srcdir}.tar.gz"
				;;
			*'2020')
				shvr_fetch "https://github.com/ksh2020/ksh/archive/refs/tags/${fork_version}.tar.gz" "${build_srcdir}.tar.gz"
				;;
			*'history')
				shvr_fetch "https://api.github.com/repos/ksh93/ksh93-history/tarball/${fork_version}" "${build_srcdir}.tar.gz"
				;;
		esac
	fi
}

# Install getconf wrapper to intercept kernel-dependent sysconf values.
shvr_install_getconf_wrapper ()
{
	if test -x /usr/bin/getconf && ! test -x /usr/bin/getconf.orig
	then
		cp /usr/bin/getconf /usr/bin/getconf.orig
	fi
	cp "${SHVR_DIR_SELF}/patches/ksh/_common/getconf-wrapper.sh" /usr/bin/getconf
	chmod +x /usr/bin/getconf
}

# Restore the original getconf after ksh build completes.
shvr_uninstall_getconf_wrapper ()
{
	if test -x /usr/bin/getconf.orig
	then
		mv /usr/bin/getconf.orig /usr/bin/getconf
	fi
}

shvr_build_ksh ()
{
	shvr_versioninfo_ksh "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	if test -d "${SHVR_DIR_SELF}/patches/ksh/$version"
	then
		find "${SHVR_DIR_SELF}/patches/ksh/$version" -type f -o -type l | sort | while read -r patch_file
		do patch -p0 < "$patch_file"
		done
	fi

	export SOURCE_DATE_EPOCH=1
	export TZ=UTC

	find "${build_srcdir}" -type f -exec touch -d "@1" {} \;

	if test -f "bin/package" && shvr_static_ksh "$1"
	then
		# Static musl build for 93u+m variants

		shvr_install_getconf_wrapper

		# Replace dylink.sh with a no-op - we only need static binaries
		if test -f "src/cmd/INIT/dylink.sh"
		then
			printf '#!/bin/sh\nexit 0\n' > "src/cmd/INIT/dylink.sh"
			chmod +x "src/cmd/INIT/dylink.sh"
		fi

		MUSL_CC="$(shvr_musl_cc)"

		export CCFLAGS="${CCFLAGS:-} -ffile-prefix-map=${build_srcdir}=. -fno-asynchronous-unwind-tables -frandom-seed=1 -fno-tree-vectorize -fno-tree-slp-vectorize"
		export LDFLAGS="-Wl,--build-id=none"

		# bin/package needs tools findable by short name.
		# cc wrapper injects -static (except when -shared is tested).
		# ar/ranlib are symlinks — deterministic mode is already the
		# default (musl-cross-make configures --enable-deterministic-archives).
		mkdir -p "${build_srcdir}/.shvr_bins"

		cat > "${build_srcdir}/.shvr_bins/cc" << EOF
#!/bin/sh
case " \$* " in
*' -shared '*) exec "${MUSL_CC}" "\$@" ;;
*)             exec "${MUSL_CC}" -static "\$@" ;;
esac
EOF
		chmod +x "${build_srcdir}/.shvr_bins/cc"

		ln -s "$(shvr_musl_ar)" "${build_srcdir}/.shvr_bins/ar"
		ln -s "$(shvr_musl_ranlib)" "${build_srcdir}/.shvr_bins/ranlib"

		export TMPDIR="${build_srcdir}/.shvr_tmp"
		mkdir -p "${TMPDIR}"

		bin/package make \
			CC="${build_srcdir}/.shvr_bins/cc" \
			AR="${build_srcdir}/.shvr_bins/ar" \
			RANLIB="${build_srcdir}/.shvr_bins/ranlib"

		unset TMPDIR

		host_type="$(bin/package host type)"
		if ! test -f "arch/${host_type}/bin/ksh"
		then
			host_type="$(find arch -path '*/bin/ksh' -type f 2>/dev/null | head -1 | cut -d/ -f2)"
		fi

		unset CCFLAGS LDFLAGS
		shvr_uninstall_getconf_wrapper

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		cp "arch/${host_type}/bin/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"

		"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	elif test -f "bin/package"
	then
		# Dynamic glibc build for history and other bin/package variants
		export CCFLAGS="${CCFLAGS:-} -ffile-prefix-map=${build_srcdir}=."
		export LDFLAGS="-Wl,--build-id=none"

		shvr_install_getconf_wrapper

		export TMPDIR="${build_srcdir}/.shvr_tmp"
		mkdir -p "${TMPDIR}"

		if test "$fork_name" = "shvrChistory"
		then
			bin/package make CC=gcc-12
			host_type="gnu.i386-64"
		else
			bin/package make CC=/usr/bin/gcc
			host_type="$(bin/package host type)"
			if ! test -f "arch/${host_type}/bin/ksh"
			then
				host_type="$(find arch -path '*/bin/ksh' -type f 2>/dev/null | head -1 | cut -d/ -f2)"
			fi
		fi

		unset TMPDIR
		unset CCFLAGS LDFLAGS
		shvr_uninstall_getconf_wrapper

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		cp "arch/${host_type}/bin/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"

		/usr/bin/strip --strip-all "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	elif test -f "meson.build"
	then
		export LDFLAGS="-Wl,--build-id=none"
		meson \
			--prefix="${SHVR_DIR_OUT}/ksh_$version" \
			-Db_lto=false \
			build

		ninja -C build

		unset LDFLAGS

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		cp "build/src/cmd/ksh93/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"

		/usr/bin/strip --strip-all "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	fi
	touch -d "@1" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	chmod 755 "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"

	unset SOURCE_DATE_EPOCH TZ

	"${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" -c "echo ksh version $version"
}

shvr_deps_ksh ()
{
	shvr_versioninfo_ksh "$1"
	case "$fork_name" in
		*'93uplusm')
			apt-get -y install \
				curl patch
			;;
		*'2020')
			apt-get -y install \
				curl gcc meson
			;;
		*'history')
			apt-get -y install \
				curl gcc-12 patch
			;;
	esac
}
