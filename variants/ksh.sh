#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"

shvr_static_ksh ()
{
	shvr_versioninfo_ksh "$1"
	test "$fork" = live
}

shvr_current_ksh ()
{
	shvr_read_versions ksh current
}

# .current lineage: keep only the live 93u+m fork (each release is its own lineage),
# so `latest` tracks the newest 93u+m releases and excludes the frozen 2020/history
# forks. Decoupled from .all (which has no shvr_series_ksh and keeps every fork/patch).
shvr_current_lineage_ksh ()
{
	shvr_versioninfo_ksh "$1"
	case "$fork" in
		live) printf '%s\n' "$1" ;;
		*)    return 1 ;;
	esac
}

shvr_targets_ksh ()
{
	shvr_read_versions ksh all
}

# Discovers the live GitHub-release forks and maps each tag to its native name.
# The ksh93/ksh fork (live) emits <semver>-uplusm; the abandoned ksh2020 fork
# emits its single 0.2020-uplus. The ksh93-history fork is a frozen archive of
# ~200 dated snapshots from which only a hand-picked set of milestones is
# supported (their canonical-dated entries live in versions/ksh.all); those are
# never re-discovered here and survive across updates via shvr_merge_versions'
# existing-union-discovered merge, which preserves any existing entry not in the
# discovered stream (and keeps its committed date).
shvr_update_ksh ()
{
	. "${SHVR_DIR_SELF}/common/version_sources/github_releases.sh"
	{
		# The helper emits "<version> <date>"; the sed rewrites only the version
		# column. ksh93/ksh tag v1.0.10 -> "1.0.10-uplusm"; ksh2020/ksh's lone
		# 2020.0.0 -> "0.2020-uplus" (named for its u+ lineage, sorted under 1.x).
		shvr_versions_from_github_tags ksh93/ksh   '^v([0-9.]+)$' | sed 's/^[0-9.]*/&-uplusm/'
		shvr_versions_from_github_tags ksh2020/ksh '^([0-9.]+)$'  | sed 's/^2020\.0\.0/0.2020-uplus/'
	} | shvr_merge_versions ksh
}

# Versions are named by their native ksh token (see KSH.md):
#   <semver>-uplusm   the live ksh93/ksh fork (93u+m), e.g. 1.0.10-uplusm
#   0.2020-uplus      the abandoned ksh2020/ksh fork (a u+ fork)
#   0.<year>-<letter> a ksh93-history snapshot, e.g. 0.2012-uplus (93u+), 0.2014-vminus
# The fork is implicit in the name shape; this derives it plus the upstream ref.
shvr_versioninfo_ksh ()
{
	version="$1"
	case "$version" in
		*-uplusm)     fork=live;    fork_ref="v${version%-uplusm}" ;;
		0.2020-uplus) fork=2020;    fork_ref="2020.0.0" ;;
		0.*)          fork=history; fork_ref="$(shvr_ksh_hist_tag "$version")" ;;
		*)            fork=live;    fork_ref="v${version}" ;;
	esac
	build_srcdir="${SHVR_DIR_SRC}/ksh/${version}"
}

# Map a history milestone name to the ksh93-history git ref to download. The repo
# carries two refs per snapshot -- a `b_<date>` beta tag and a bare `<date>` ref
# that point at *different* trees (the beta tag is the buildable one the patches
# and checksums were made against); we use `b_<date>`. The name's <year> is the
# *release* year (from SH_RELEASE); the ref date is the *snapshot* date, which can
# be later (the 93v- release, 2014-12-24, was tagged b_2016-01-10).
shvr_ksh_hist_tag ()
{
	case "$1" in
		0.2007-s)      echo b_2007-01-11 ;;
		0.2008-splus)  echo b_2008-02-02 ;;
		0.2008-tminus) echo b_2008-06-08 ;;
		0.2008-t)      echo b_2008-11-04 ;;
		0.2010-tplus)  echo b_2010-06-21 ;;
		0.2010-uminus) echo b_2010-10-26 ;;
		0.2011-u)      echo b_2011-03-10 ;;
		0.2012-uplus)  echo b_2012-08-01 ;;
		0.2014-vminus) echo b_2016-01-10 ;;
	esac
}

shvr_download_ksh ()
{
	shvr_versioninfo_ksh "$1"

	mkdir -p "${SHVR_DIR_SRC}/ksh"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		case "$fork" in
			live)
				shvr_fetch "https://github.com/ksh93/ksh/archive/refs/tags/${fork_ref}.tar.gz" "${build_srcdir}.tar.gz"
				;;
			2020)
				shvr_fetch "https://github.com/ksh2020/ksh/archive/refs/tags/${fork_ref}.tar.gz" "${build_srcdir}.tar.gz"
				;;
			history)
				shvr_fetch "https://api.github.com/repos/ksh93/ksh93-history/tarball/${fork_ref}" "${build_srcdir}.tar.gz"
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

	# libast's conf.tab PID_MAX probe reads the build host's
	# /proc/sys/kernel/pid_max at build time and bakes the result into ksh's
	# getconf table. That value is kernel-config-dependent (Docker Desktop's
	# linuxkit VM reports 99999, a default Linux host reports 4194304), so it
	# silently breaks cross-host reproducibility — and the getconf(1) wrapper
	# cannot intercept this direct /proc read. Pin it to the standard Linux
	# 64-bit default (4194304), which is exactly what a default host, the CI
	# runners and the getconf wrapper already yield, so amd64 and existing
	# arm64 CI outputs are unchanged.
	if test -f src/lib/libast/comp/conf.tab
	then
		# Pin every form of the PID_MAX value the probe can settle on: the
		# #ifdef branch (v = PID_MAX), the newer #else fallback (v = 99999) and
		# the older history-fork fallback (v = -1) all become 4194304, and the
		# /proc read is neutered. Without the -1 case the older fork would bake
		# -1 (the probe's stdout is what conf.sh captures), differing from the
		# 4194304 a default host's /proc already yields and breaking the amd64
		# checksums too. 'v = -1;' occurs only in this block in the affected
		# version, and is absent (no-op) in all others.
		sed -i \
			-e 's#open("/proc/sys/kernel/pid_max", 0)#open("/nonexistent/shvr-pinned-pid-max", 0)#' \
			-e 's/v = PID_MAX;/v = 4194304;/' \
			-e 's/v = 99999;/v = 4194304;/' \
			-e 's/v = -1;/v = 4194304;/' \
			src/lib/libast/comp/conf.tab
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

		if test "$fork" = history
		then
			bin/package make CC=gcc-12
			# bin/package builds into arch/<host_type>/ where host_type is
			# arch-derived (gnu.i386-64 on amd64, gnu.aarch64 on arm64), so
			# discover it from the built tree instead of hardcoding.
			host_type="$(find arch -path '*/bin/ksh' -type f 2>/dev/null | head -1 | cut -d/ -f2)"
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
	case "$fork" in
		live)
			apt-get -y install \
				curl patch
			;;
		2020)
			apt-get -y install \
				curl gcc meson
			;;
		history)
			apt-get -y install \
				curl gcc-12 patch
			;;
	esac
}
