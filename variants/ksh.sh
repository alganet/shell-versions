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
	# -frandom-seed=0: Ensure consistent random seed for hash tables and such
	# -fno-tree-vectorize/-fno-tree-slp-vectorize: Avoid compiler auto-vectorized constant pools that can vary across builds
	# -Wl,--build-id=none: Remove build IDs which contain timestamps
	# Note: -static is handled by the cc wrapper (not LDFLAGS) to
	# avoid conflicts with -shared when building .dll/.so files
	export CCFLAGS="${CCFLAGS:-} -fno-asynchronous-unwind-tables -frandom-seed=0 -fno-tree-vectorize -fno-tree-slp-vectorize"
	export CFLAGS="${CFLAGS:-} -fno-asynchronous-unwind-tables -frandom-seed=0 -fno-tree-vectorize -fno-tree-slp-vectorize"
	export CXXFLAGS="${CXXFLAGS:-} -fno-asynchronous-unwind-tables -frandom-seed=0 -fno-tree-vectorize -fno-tree-slp-vectorize"
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

	# Add wrapper scripts to PATH before package script and directly
	export AR="${build_srcdir}/.shvr_bins/ar"
	export RANLIB="${build_srcdir}/.shvr_bins/ranlib"
	export PATH="${build_srcdir}/.shvr_bins:${PATH}"

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

	# Strip binary to ensure reproducible output (use musl strip)
	"$(shvr_musl_strip)" --strip-all "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"
	chmod 755 "${SHVR_DIR_OUT}/ksh_${version}/bin/ksh"

	unset SOURCE_DATE_EPOCH TZ

	"${SHVR_DIR_OUT}/ksh_${version}/bin/ksh" -c "echo ksh version $version"
}

shvr_deps_ksh ()
{
	shvr_versioninfo_ksh "$1"
	apt-get -y install \
		curl gcc g++ make patch xz-utils bzip2
}
