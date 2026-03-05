#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/musl-cross-make.sh"

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
		shvr_fetch "https://github.com/ksh93/ksh/archive/refs/tags/${fork_version}.tar.gz" "${build_srcdir}.tar.gz"
	fi

	shvr_download_musl_cross_make
}

shvr_build_ksh ()
{
	shvr_versioninfo_ksh "$1"

	shvr_build_musl_cross_make

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	# Skip shared library creation - we only need static binaries.
	# Replace dylink.sh with a no-op before it gets installed to arch/bin/
	if test -f "src/cmd/INIT/dylink.sh"
	then
		printf '#!/bin/sh\nexit 0\n' > "src/cmd/INIT/dylink.sh"
		chmod +x "src/cmd/INIT/dylink.sh"
	fi

	# Set reproducible build environment
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC

	# Normalize all file timestamps in source directory to epoch 1 before build
	find "${build_srcdir}" -type f -exec touch -d "@1" {} \;

	MUSL_CC="$(shvr_musl_cc)"
	MUSL_AR="$(shvr_musl_ar)"
	MUSL_RANLIB="$(shvr_musl_ranlib)"

	# Set additional reproducible build flags for package system
	# -fno-asynchronous-unwind-tables: Remove non-deterministic unwind tables
	# -frandom-seed=1: Ensure consistent random seed for hash tables and such
	# -fno-tree-vectorize/-fno-tree-slp-vectorize: Avoid compiler auto-vectorized constant pools that can vary across builds
	# -ffile-prefix-map: Normalize build paths in the binary
	# -Wl,--build-id=none: Remove build IDs which contain timestamps
	# Note: -static is handled by the cc wrapper (not LDFLAGS) to
	# avoid conflicts with -shared when building .dll/.so files
	export CCFLAGS="${CCFLAGS:-} -fno-asynchronous-unwind-tables -frandom-seed=1 -fno-tree-vectorize -fno-tree-slp-vectorize -ffile-prefix-map=${build_srcdir}=."
	export CFLAGS="${CFLAGS:-} -fno-asynchronous-unwind-tables -frandom-seed=1 -fno-tree-vectorize -fno-tree-slp-vectorize -ffile-prefix-map=${build_srcdir}=."
	export CXXFLAGS="${CXXFLAGS:-} -fno-asynchronous-unwind-tables -frandom-seed=1 -fno-tree-vectorize -fno-tree-slp-vectorize -ffile-prefix-map=${build_srcdir}=."
	export LDFLAGS="-Wl,--build-id=none"

	# Create wrapper scripts for cc, ar, and ranlib
	# The cc wrapper always passes -static so that bin/package's
	# cross-compiler test produces a runnable static binary
	mkdir -p "${build_srcdir}/.shvr_bins"
	cat > "${build_srcdir}/.shvr_bins/cc" << EOF
#!/bin/sh
# Add -static unless building a shared library
case " \$* " in
*' -shared '*) exec "${MUSL_CC}" "\$@" ;;
*)             exec "${MUSL_CC}" -static "\$@" ;;
esac
EOF
	chmod +x "${build_srcdir}/.shvr_bins/cc"
	touch -d "@1" "${build_srcdir}/.shvr_bins/cc"

	cat > "${build_srcdir}/.shvr_bins/ar" << EOF
#!/bin/sh
exec ${MUSL_AR} -D "\$@"
EOF
	chmod +x "${build_srcdir}/.shvr_bins/ar"
	touch -d "@1" "${build_srcdir}/.shvr_bins/ar"

	cat > "${build_srcdir}/.shvr_bins/ranlib" << EOF
#!/bin/sh
exec ${MUSL_RANLIB} -D "\$@"
EOF
	chmod +x "${build_srcdir}/.shvr_bins/ranlib"
	touch -d "@1" "${build_srcdir}/.shvr_bins/ranlib"

	# Skip shared library creation (dylink) - we only need static binaries
	cat > "${build_srcdir}/.shvr_bins/dylink" << 'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "${build_srcdir}/.shvr_bins/dylink"
	touch -d "@1" "${build_srcdir}/.shvr_bins/dylink"

	# getconf wrapper for reproducible builds.
	# ksh's conf.sh uses getconf(1) to discover system limits like
	# ARG_MAX, CHILD_MAX, PID_MAX. These are kernel-dependent and
	# vary across CI runners, making FEATURE/limits non-deterministic.
	# conf.sh checks DEFPATH (/bin:/usr/bin) before PATH, so we must
	# replace /usr/bin/getconf. Back up the original first.
	if test -x /usr/bin/getconf && ! test -x /usr/bin/getconf.orig
	then
		cp /usr/bin/getconf /usr/bin/getconf.orig
	fi
	cat > /usr/bin/getconf << 'EOF'
#!/bin/sh
# Fixed getconf wrapper for reproducible builds.
# Intercepts kernel-dependent values; delegates everything else.
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
EOF
	chmod +x /usr/bin/getconf

	# Add wrapper scripts to PATH before package script and directly
	export AR="${build_srcdir}/.shvr_bins/ar"
	export RANLIB="${build_srcdir}/.shvr_bins/ranlib"
	export PATH="${build_srcdir}/.shvr_bins:${PATH}"

	# Patch timing-dependent feature tests for reproducible builds.
	#
	# features/mmap: The output{} test benchmarks read() vs mmap() and
	# outputs different #define values depending on timing results.
	# Replace with a static cat{} that always defines _mmap_worthy=2.
	if test -f "src/lib/libast/features/mmap"
	then
		awk '
		/^tst.*mmap is fast enough/ {
			skip=1
			print "cat{"
			print "#define _mmap_worthy\t2\t/* forced for reproducible builds */"
			next
		}
		skip && /^}end/ { skip=0 }
		skip { next }
		{ print }
		' "src/lib/libast/features/mmap" > "src/lib/libast/features/mmap.tmp" &&
		mv "src/lib/libast/features/mmap.tmp" "src/lib/libast/features/mmap"
		touch -d "@1" "src/lib/libast/features/mmap"
	fi
	# features/tvlib: The prefer_poll execute{} test measures select()
	# precision with a 1µs timeout. Results vary across CI runners.
	# Make it always succeed so _prefer_poll is consistently defined.
	if test -f "src/lib/libast/features/tvlib"
	then
		awk '
		/^tst	prefer_poll/ {
			print "tst\tprefer_poll note{ forced for reproducible builds }end execute{"
			print "\tint main(void) { return 0; }"
			skip=1
			next
		}
		skip && /^}end/ { skip=0 }
		skip { next }
		{ print }
		' "src/lib/libast/features/tvlib" > "src/lib/libast/features/tvlib.tmp" &&
		mv "src/lib/libast/features/tvlib.tmp" "src/lib/libast/features/tvlib"
		touch -d "@1" "src/lib/libast/features/tvlib"
	fi
	# features/float: The "long double exponent bitfoolery" output{}
	# test examines bit patterns of long double values 1.0L and 2.0L.
	# On x86_64, long double is 80-bit stored in 128 bits; the 6
	# padding bytes contain undefined garbage. Different runs can
	# produce different padding, causing the test to silently fail
	# (no output) when garbage differs between the two values.
	# Force the correct x86_64 values.
	if test -f "src/lib/libast/features/float"
	then
		awk '
		/long double exponent bitfoolery/ {
			print "cat{"
			print "typedef union _fltmax_exp_u"
			print "{"
			print "\tuint32_t\t\te[sizeof(_ast_fltmax_t)/4];"
			print "\t_ast_fltmax_t\t\tf;"
			print "} _ast_fltmax_exp_t;"
			print ""
			print "#define _ast_fltmax_exp_index\t2"
			print "#define _ast_fltmax_exp_shift\t0"
			print ""
			skip=1
			next
		}
		skip && /^}end/ { skip=0 }
		skip { next }
		{ print }
		' "src/lib/libast/features/float" > "src/lib/libast/features/float.tmp" &&
		mv "src/lib/libast/features/float.tmp" "src/lib/libast/features/float"
		touch -d "@1" "src/lib/libast/features/float"
	fi

	# Set TMPDIR inside the build tree to avoid noexec /tmp in Docker
	export TMPDIR="${build_srcdir}/.shvr_tmp"
	mkdir -p "${TMPDIR}"
	bin/package make CC="${build_srcdir}/.shvr_bins/cc" "AR=${build_srcdir}/.shvr_bins/ar" "RANLIB=${build_srcdir}/.shvr_bins/ranlib"
	unset TMPDIR
	# Detect the arch directory used by the build system.
	# Older ksh versions (pre-1.0.6) create arch/musl.* but
	# "bin/package host type" reports linux.* instead.
	host_type="$(bin/package host type)"
	if ! test -f "arch/${host_type}/bin/ksh"
	then
		host_type="$(find arch -path '*/bin/ksh' -type f 2>/dev/null | head -1 | cut -d/ -f2)"
	fi

	unset CCFLAGS CFLAGS CXXFLAGS AR RANLIB LDFLAGS

	mkdir -p "${SHVR_DIR_OUT}/ksh_${version}/bin"
	cp "arch/${host_type}/bin/ksh" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"

	# Log pre-strip diagnostics
	shvr_log_build_env
	(
		set +x
		echo "=== ksh ${version} ==="
		echo "--- host_type ---"
		echo "${host_type}"
		echo "--- FEATURE file checksums ---"
		find "arch/${host_type}" -name 'FEATURE' -type d 2>/dev/null |
			while read -r fdir; do
				find "$fdir" -type f | sort | while read -r ff; do
					sha256sum "$ff"
				done
			done
		echo "--- FEATURE/lib content (libast) ---"
		cat "arch/${host_type}/src/lib/libast/FEATURE/lib" 2>/dev/null || echo "(not found)"
		echo "--- FEATURE/float content (libast) ---"
		cat "arch/${host_type}/src/lib/libast/FEATURE/float" 2>/dev/null || echo "(not found)"
		echo "--- FEATURE/limits content (libast) ---"
		cat "arch/${host_type}/src/lib/libast/FEATURE/limits" 2>/dev/null || echo "(not found)"
		echo "--- FEATURE/mmap content (libast) ---"
		cat "arch/${host_type}/src/lib/libast/FEATURE/mmap" 2>/dev/null || echo "(not found)"
		echo "--- releaseflags.h ---"
		cat "arch/${host_type}/src/lib/libast/releaseflags.h" 2>/dev/null || echo "(not found)"
		echo "--- mamprobe info ---"
		cat "arch/${host_type}/lib/probe/C/mam/"* 2>/dev/null || echo "(not found)"
		echo "--- arch lib checksums ---"
		find "arch/${host_type}/lib" -name '*.a' -type f 2>/dev/null | sort | while read -r lf; do
			sha256sum "$lf"
		done
		echo "--- ksh binary SHA256 (pre-strip) ---"
		sha256sum "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	) >> "${SHVR_DIR_OUT}/shvr/build-env.log" 2>&1

	# Strip binary to ensure reproducible output (use musl strip)
	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	chmod 755 "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"

	# Log post-strip checksum
	(
		set +x
		echo "--- ksh binary SHA256 (post-strip) ---"
		sha256sum "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	) >> "${SHVR_DIR_OUT}/shvr/build-env.log" 2>&1

	unset SOURCE_DATE_EPOCH TZ

	"${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" -c "echo ksh version $version"
}

shvr_deps_ksh ()
{
	shvr_versioninfo_ksh "$1"
	apt-get -y install \
		curl gcc g++ make patch xz-utils bzip2
}
