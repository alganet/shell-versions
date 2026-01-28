#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

. "${SHVR_DIR_SELF}/common/rustup.sh"

shvr_current_brush ()
{
	cat <<-@
		brush_0.3.0
		brush_0.2.23
	@
}

shvr_targets_brush ()
{
	cat <<-@
		brush_0.3.0
		brush_0.2.23
	@
}

shvr_versioninfo_brush ()
{
	version="$1"
	build_srcdir="${SHVR_DIR_SRC}/brush/${version}"
}

shvr_download_brush ()
{
	shvr_versioninfo_brush "$1"

	shvr_download_rustup

	mkdir -p "${SHVR_DIR_SRC}/brush"

	if ! test -f "${build_srcdir}.tar.gz"
	then
		shvr_fetch "https://github.com/reubeno/brush/archive/refs/tags/brush-shell-v${version}.tar.gz" "${build_srcdir}.tar.gz"
	fi
}

shvr_build_brush ()
{
	. "$HOME/.cargo/env"

	shvr_versioninfo_brush "$1"

	mkdir -p "${build_srcdir}"

	tar --extract \
		--file="${build_srcdir}.tar.gz" \
		--strip-components=1 \
		--directory="${build_srcdir}" \
		--owner=0 \
		--group=0 \
		--mode=go-w \
		--touch

	cd "${build_srcdir}"

	# Build with reproducible flags
	# Use fixed source date epoch and disable compiler timestamp features
	export SOURCE_DATE_EPOCH=1
	export TZ=UTC
	export RUSTFLAGS="-A unused_imports -C target-feature=-crt-static"

	cargo build --release

	unset SOURCE_DATE_EPOCH TZ RUSTFLAGS

	mkdir -p "${SHVR_DIR_OUT}/brush_${version}/bin"
	cp "./target/release/brush" "${SHVR_DIR_OUT}/brush_$version/bin"

	# Strip binary to ensure reproducible output
	strip --strip-all "${SHVR_DIR_OUT}/brush_${version}/bin/brush"

	# Ensure consistent permissions and timestamps
	touch -d "@1" "${SHVR_DIR_OUT}/brush_${version}/bin/brush"
	chmod 755 "${SHVR_DIR_OUT}/brush_${version}/bin/brush"

	"${SHVR_DIR_OUT}/brush_${version}/bin/brush" -c "echo brush version $version"
}

shvr_deps_brush ()
{
	shvr_versioninfo_brush "$1"
	apt-get -y install \
		curl gcc binutils

	if ! test -f "$HOME/.cargo/env"
	then
		shvr_download_rustup
		sh "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh" -y
	fi
}
