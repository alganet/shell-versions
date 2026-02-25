#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

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
		ksh_shvrB2020-2020.0.0
		ksh_shvrChistory-b_2016-01-10
		ksh_shvrChistory-b_2012-08-01
		ksh_shvrChistory-b_2011-03-10
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

shvr_build_ksh ()
{
	shvr_versioninfo_ksh "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"
	saved_path="$PATH"

	if test -d "${SHVR_DIR_SELF}/patches/ksh/$version"
	then
		find "${SHVR_DIR_SELF}/patches/ksh/$version" -type f | sort | while read -r patch_file
		do patch -p0 < "$patch_file"
		done
	fi

	# Set reproducible build environment
	saved_umask="$(umask)"
	umask 022
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export LC_ALL=C
	export LANG=C
	export ZERO_AR_DATE=1
	export MAKEFLAGS=-j1
	export MAMAKEFLAGS=-j1
	export MFLAGS=
	det_cppflags="-Wno-builtin-macro-redefined -D__DATE__=\"1970-01-01\" -D__TIME__=\"00:00:00\" -D__TIMESTAMP__=\"1970-01-01T00:00:01Z\" -ffile-prefix-map=${build_srcdir}=. -fno-ident"
	export CPPFLAGS="${det_cppflags}"
	export CFLAGS="${det_cppflags}"
	export CCFLAGS="${det_cppflags}"
	export CXXFLAGS="${det_cppflags}"
	saved_ulimit_n="$(ulimit -n 2>/dev/null || echo '')"
	saved_nproc="${NPROC-}"
	saved_tmpdir="${TMPDIR-}"
	export TMPDIR="${build_srcdir}/.shvr_tmp"
	mkdir -p "$TMPDIR"
	touch -d "@1" "$TMPDIR"

	# Normalize all file timestamps in source directory to epoch 1 before build
	find "${build_srcdir}" -exec touch -d "@1" {} \;

	if test -f "bin/package"
	then
		# Keep fd-related probes stable even if the outer runner has a very
		# large or variable RLIMIT_NOFILE.
		ulimit -n 1024 2>/dev/null || true

		# libast/comp/conf.sh probes getconf(1) runtime values (OPEN_MAX,
		# CHILD_MAX, etc.) and bakes them into generated headers. Those values
		# can vary by runner environment even with identical sources/toolchain.
		# Reset CONF_getconf after detection to force compile-time constants.
		if test -f "src/lib/libast/comp/conf.sh"
		then
			if ! grep -q 'SHVR deterministic limits' "src/lib/libast/comp/conf.sh"
			then
				awk '
					BEGIN { inserted = 0 }
					{
						print
						if ($0 ~ /^export[[:space:]]+CONF_getconf[[:space:]]+CONF_getconf_a$/) {
							print ""
							print "# SHVR deterministic limits: avoid runtime getconf(1) variability."
							print "CONF_getconf="
							print "CONF_getconf_a="
							inserted = 1
						}
					}
					END {
						if (!inserted) {
							print ""
							print "# SHVR deterministic limits: avoid runtime getconf(1) variability."
							print "CONF_getconf="
							print "CONF_getconf_a="
						}
					}
				' "src/lib/libast/comp/conf.sh" > "src/lib/libast/comp/conf.sh.tmp"
				mv "src/lib/libast/comp/conf.sh.tmp" "src/lib/libast/comp/conf.sh"
				touch -d "@1" "src/lib/libast/comp/conf.sh"
			fi
		fi

		# Force the release code path in version.h so git/working-tree state
		# does not leak into the binary version string ("+<hash>" or "/MOD").
		stable_release_flags='-D_AST_release=1 -U_AST_git_commit'

		# Set additional reproducible build flags for package system
		# -fno-asynchronous-unwind-tables: Remove non-deterministic unwind tables
		# -frandom-seed=0: Ensure consistent random seed for hash tables and such
		# -fno-tree-vectorize/-fno-tree-slp-vectorize: Avoid compiler auto-vectorized constant pools that can vary across builds
		# -Wl,--build-id=none: Remove build IDs which contain timestamps
		det_optflags="${stable_release_flags} -fno-asynchronous-unwind-tables -frandom-seed=0 -fno-tree-vectorize -fno-tree-slp-vectorize"
		export CCFLAGS="${CCFLAGS} ${det_optflags}"
		export CFLAGS="${CFLAGS} ${det_optflags}"
		export CXXFLAGS="${CXXFLAGS} ${det_optflags}"
		export LDFLAGS="-Wl,--build-id=none"
		export NPROC=1

		if test "$fork_name" = "shvrChistory"
		then
			base_compiler="/usr/bin/gcc-12"
		else
			base_compiler="/usr/bin/gcc"
		fi

		# Create wrapper scripts so package/mamake cannot bypass deterministic flags.
		mkdir -p "${build_srcdir}/.shvr_bins"
		cat > "${build_srcdir}/.shvr_bins/ar" << 'EOF'
#!/bin/sh
exec /usr/bin/ar -D "$@"
EOF
		chmod +x "${build_srcdir}/.shvr_bins/ar"
		touch -d "@1" "${build_srcdir}/.shvr_bins/ar"

		cat > "${build_srcdir}/.shvr_bins/ranlib" << 'EOF'
#!/bin/sh
exec /usr/bin/ranlib -D "$@"
EOF
		chmod +x "${build_srcdir}/.shvr_bins/ranlib"
		touch -d "@1" "${build_srcdir}/.shvr_bins/ranlib"

		cat > "${build_srcdir}/.shvr_bins/cc" << EOF
#!/bin/sh
exec ${base_compiler} ${det_cppflags} ${det_optflags} -Wl,--build-id=none "\$@"
EOF
		chmod +x "${build_srcdir}/.shvr_bins/cc"
		touch -d "@1" "${build_srcdir}/.shvr_bins/cc"

		for cc_name in gcc gcc-12
		do
			cat > "${build_srcdir}/.shvr_bins/${cc_name}" << EOF
#!/bin/sh
exec "${build_srcdir}/.shvr_bins/cc" "\$@"
EOF
			chmod +x "${build_srcdir}/.shvr_bins/${cc_name}"
			touch -d "@1" "${build_srcdir}/.shvr_bins/${cc_name}"
		done

		# Add wrapper scripts to PATH before package script and directly
		export AR="${build_srcdir}/.shvr_bins/ar"
		export RANLIB="${build_srcdir}/.shvr_bins/ranlib"
		export CC="${build_srcdir}/.shvr_bins/cc"
		export PATH="${build_srcdir}/.shvr_bins:${PATH}"

		bin/package make "CC=${build_srcdir}/.shvr_bins/cc" "AR=${build_srcdir}/.shvr_bins/ar" "RANLIB=${build_srcdir}/.shvr_bins/ranlib"

		unset AR RANLIB CC LDFLAGS stable_release_flags det_optflags base_compiler
		if test -n "$saved_nproc"
		then
			export NPROC="$saved_nproc"
		else
			unset NPROC
		fi

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		host_ksh_path="$(find arch -type f -path '*/bin/ksh' | sort | head -n1)"
		if test -n "$host_ksh_path"
		then
			cp "$host_ksh_path" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
		else
			echo "ksh binary not found under arch/*/bin/ksh for $version" >&2
			return 1
		fi

		# Persist package-generated limit/config metadata for CI diagnostics.
		mkdir -p "${SHVR_DIR_OUT}/shvr/ksh-determinism"
		ast_limits_path="$(find arch -type f -path '*/include/ast/ast_limits.h' | sort | head -n1)"
		det_file="${SHVR_DIR_OUT}/shvr/ksh-determinism/${version}.txt"
		{
			echo "version=${version}"
			echo "fork=${fork_name}"
			echo "tmpdir=${TMPDIR}"
			echo "cc_path=$(command -v cc 2>/dev/null || true)"
			echo "gcc_path=$(command -v gcc 2>/dev/null || true)"
			echo "gcc12_path=$(command -v gcc-12 2>/dev/null || true)"
			echo "cc_version=$(${build_srcdir}/.shvr_bins/cc --version 2>/dev/null | head -n1 || true)"
			echo "ulimit_n=$(ulimit -n 2>/dev/null || true)"
			echo "getconf_OPEN_MAX=$(getconf OPEN_MAX 2>/dev/null || true)"
			echo "getconf_CHILD_MAX=$(getconf CHILD_MAX 2>/dev/null || true)"
			echo "conf_patch_marker_count=$(grep -c 'SHVR deterministic limits' src/lib/libast/comp/conf.sh 2>/dev/null || true)"
			arch_include_hash="$(find arch -type f -path '*/include/*' | sort | while read -r f; do sha256sum "$f"; done | sha256sum | awk '{print $1}')"
			echo "arch_include_tree_sha256=${arch_include_hash}"
			if test -n "$ast_limits_path"
			then
				echo "ast_limits_path=${ast_limits_path}"
				echo "--- ast_limits key defines ---"
				grep -E '^#define (CHILD_MAX|OPEN_MAX|OPEN_MAX_CEIL|FD_PRIVATE|FOPEN_MAX|STREAM_MAX|PATH_MAX|NAME_MAX|TMP_MAX|IOV_MAX)' "$ast_limits_path" || true
			fi
		} > "$det_file"
		touch -d "@1" "$det_file"
		if test -n "$ast_limits_path"
		then
			cp "$ast_limits_path" "${SHVR_DIR_OUT}/shvr/ksh-determinism/${version}.ast_limits.h"
			touch -d "@1" "${SHVR_DIR_OUT}/shvr/ksh-determinism/${version}.ast_limits.h"
		fi
	elif test -f "meson.build"
	then
		# Set meson to use reproducible build options
		export LDFLAGS="-Wl,--build-id=none"
		meson \
			--prefix="${SHVR_DIR_OUT}/ksh_$version" \
			-Db_lto=false \
			build

		ninja -C build

		unset LDFLAGS

		mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
		cp "build/src/cmd/ksh93/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	fi

	# Canonicalize binary metadata to reduce toolchain/version-specific drift.
	if command -v strip >/dev/null 2>&1
	then
		strip --strip-all "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	fi
	if command -v objcopy >/dev/null 2>&1
	then
		objcopy --remove-section=.comment "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" 2>/dev/null || true
		objcopy --remove-section=.note.gnu.build-id "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" 2>/dev/null || true
		objcopy --remove-section=.note.gnu.property "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" 2>/dev/null || true
		objcopy --remove-section=.note.ABI-tag "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" 2>/dev/null || true
	fi

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	chmod 755 "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"

	unset SOURCE_DATE_EPOCH TZ LC_ALL LANG ZERO_AR_DATE MAKEFLAGS MAMAKEFLAGS MFLAGS CPPFLAGS CFLAGS CCFLAGS CXXFLAGS det_cppflags TMPDIR
	if test -n "$saved_nproc"
	then
		export NPROC="$saved_nproc"
	else
		unset NPROC
	fi
	if test -n "$saved_tmpdir"
	then
		export TMPDIR="$saved_tmpdir"
	else
		unset TMPDIR
	fi
	if test -n "$saved_ulimit_n"
	then
		ulimit -n "$saved_ulimit_n" 2>/dev/null || true
	fi
	PATH="$saved_path"
	umask "$saved_umask"

	"${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" -c "echo ksh version $version"
}

shvr_deps_ksh ()
{
	shvr_versioninfo_ksh "$1"
	case "$fork_name" in
		*'93uplusm')
			apt-get -y install \
				binutils curl gcc patch
			;;
		*'2020')
			apt-get -y install \
				binutils curl gcc meson
			;;
		*'history')
			apt-get -y install \
				binutils curl gcc-12 patch
			;;
	esac
}
