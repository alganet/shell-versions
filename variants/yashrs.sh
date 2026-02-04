#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/rustup.sh"

shvr_current_yashrs ()
{
	cat <<-@
		yashrs_3.0.5
		yashrs_3.0.4
		yashrs_0.4.5
	@
}

shvr_targets_yashrs ()
{
	cat <<-@
		yashrs_3.0.5
		yashrs_3.0.4
		yashrs_0.4.5
	@
}

shvr_versioninfo_yashrs ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/yashrs/${version}"
}

shvr_download_yashrs ()
{
	shvr_versioninfo_yashrs "$1"
	shvr_download_rustup

	mkdir -p "${SHVR_DIR_SRC}/yashrs"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://github.com/magicant/yash-rs/archive/refs/tags/yash-cli-${version}.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_yashrs ()
{
	. "$HOME/.cargo/env"

	shvr_versioninfo_yashrs "$1"

	mkdir -p "${build_srcdir}"

	shvr_untar "${build_srcdir}.tar.gz" "${build_srcdir}"

	cd "${build_srcdir}"

	# Build with reproducible flags
	# Use fixed source date epoch and disable compiler timestamp features
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export RUSTFLAGS="-C target-feature=-crt-static"

	cargo build --release

	unset SOURCE_DATE_EPOCH TZ RUSTFLAGS

	mkdir -p "${SHVR_DIR_OUT}/yashrs_${version}/bin"
	cp "./target/release/yash3" "${SHVR_DIR_OUT}/yashrs_$version/bin"

	# Strip binary to ensure reproducible output
	strip --strip-all "${SHVR_DIR_OUT}/yashrs_${version}/bin/yash3"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/yashrs_${version}/bin/yash3"
	chmod 755 "${SHVR_DIR_OUT}/yashrs_${version}/bin/yash3"

	"${SHVR_DIR_OUT}/yashrs_${version}/bin/yash3" -c "echo yashrs version $version"
}

shvr_deps_yashrs ()
{
	shvr_versioninfo_yashrs "$1"
	apt-get -y install \
		curl gcc binutils

	if ! test -f "$HOME/.cargo/env"
	then
		shvr_download_rustup
		sh "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh" -y
	fi
}
