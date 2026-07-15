# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# Base images. Defaults are digest-pinned for reproducible local builds.
# CI overrides these with the GHCR-mirrored equivalents (same digests,
# resolved by the `mirror` job) to avoid docker.io pull rate limits.
# Bump these (and regenerate build checksums) when refreshing the base.
# Keep in sync with .github/workflows/docker.yml MIRROR_*_SOURCE.
ARG TOOLCHAIN_BASE=debian:trixie-slim@sha256:cedb1ef40439206b673ee8b33a46a03a0c9fa90bf3732f54704f99cb061d2c5a
ARG RUNTIME_BASE=busybox:stable-musl@sha256:3c6ae8008e2c2eedd141725c30b20d9c36b026eb796688f88205845ef17aa213

FROM ${TOOLCHAIN_BASE} AS toolchain

    # Build architecture, taken from BuildKit's automatic TARGETARCH (amd64|arm64),
    # so it is ALWAYS the platform being built (`buildx build --platform linux/<arch>`)
    # and can never diverge from it — there is no separate arch build-arg to keep in
    # sync. Drives the musl-cross-make target triple and the Rust target via
    # common/musl-cross-make.sh. SHVR_ARCH is exported (inherited by the builder
    # stage) for shvr.sh; the values match (TARGETARCH and SHVR_ARCH are both
    # amd64|arm64).
    ARG TARGETARCH
    ENV SHVR_ARCH=${TARGETARCH}

    # Pin apt sources to a specific snapshot.debian.org timestamp so the
    # host toolchain (gcc, binutils, etc.) is bit-identical across builds
    # and hosts. Without this, apt-get pulls live indexes and Debian
    # security updates make the resulting musl-cross-make and stock cc
    # drift over time, which propagates into every built binary. The
    # chosen date matches the snapshot reference that debian:trixie-slim
    # already records as a comment in its own debian.sources file.
    ARG DEBIAN_SNAPSHOT=20260421T000000Z
    # http (not https) because debian:trixie-slim lacks ca-certificates,
    # and apt-get install can't run before apt-get update succeeds.
    # snapshot.debian.org signs the InRelease files so integrity is still
    # verified via the digest-pinned base's keyrings.
    RUN sed -i \
            -e "s|http://deb.debian.org/debian-security|http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}|" \
            -e "s|http://deb.debian.org/debian|http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}|" \
            /etc/apt/sources.list.d/debian.sources && \
        echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

    # Update distro
    RUN apt-get -y update

    # Copy only musl-cross-make dependencies for maximum cacheability
    COPY "build/musl-cross-make-*" "/usr/src/shvr/"
    COPY "checksums/sources/musl-cross-make-*" "/shvr/checksums/sources/"
    COPY "common/musl-cross-make.sh" "/shvr/common/musl-cross-make.sh"

    # shvr.sh sources common/patches.sh unconditionally, so it is part of the
    # entry point rather than of any one variant: without it even `musl-build`,
    # which patches nothing, cannot start. Cacheability is unaffected in practice
    # because shvr.sh is copied here too and changes far more often.
    COPY "common/patches.sh" "/shvr/common/patches.sh"

    COPY "shvr.sh" "/shvr/shvr.sh"
    RUN chmod +x "/shvr/shvr.sh"

    # Setup environment
    ENV SHVR_DIR_SRC="/usr/src/shvr"
    ENV SHVR_DIR_OUT="/opt"

    # Build musl cross-compiler once (shared by all static variants)
    RUN bash "/shvr/shvr.sh" musl-build

    # Pre-install Rust toolchain (used by brush and yashrs). The toolchain
    # version is pinned so the resulting binaries are bit-identical across
    # hosts and runs; otherwise rustup-init downloads "latest stable" at
    # image-build time, which drifts and breaks cross-host reproducibility.
    # Bump when refreshing the base and regenerate the affected checksums.
    ARG RUST_TOOLCHAIN=1.96.0
    COPY "build/rustup-init-*" "/usr/src/shvr/"
    COPY "checksums/sources/rustup-init-*" "/shvr/checksums/sources/"
    RUN sh "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh" -y --default-toolchain "${RUST_TOOLCHAIN}" && \
        . "$HOME/.cargo/env" && \
        . "/shvr/common/musl-cross-make.sh" && \
        rustup target add "$(shvr_rust_target)"


# In CI this `toolchain` is NOT this file's toolchain stage. The build jobs pass
# a named build context (`--build-context toolchain=docker-image://...`) pointing
# at the image the toolchain job published, which replaces the stage wholesale, so
# musl-cross-make is compiled once per arch per run instead of once per build job.
# See the build-contexts note in .github/workflows/docker.yml.
#
# A plain `docker build` passes no such context, so the stage above is used and a
# local build still works end to end -- just slowly, the first time.
FROM toolchain AS builder

    # Copy contents
    COPY "build/" "/usr/src/shvr"
    COPY "checksums/" "/shvr/checksums"
    COPY "common/" "/shvr/common"
    COPY "patches/" "/shvr/patches"
    COPY "payloads/" "/shvr/payloads"
    COPY "variants/" "/shvr/variants"

    ARG TARGETS

    # Refresh apt index before variant deps. The toolchain layer is heavily
    # cached, and its `apt-get update` can point at packages that Debian has
    # since security-updated and removed from the mirror; without this, the
    # next `apt-get install` (from a variant's shvr_deps_<shell>) fails with
    # "404 Not Found" or "Version 'X' not found".
    RUN apt-get -y update

    # Build
    RUN bash "/shvr/shvr.sh" deps $TARGETS
    RUN bash "/shvr/shvr.sh" build $TARGETS

    # Extract unique library dependencies
    RUN mkdir -p /deps/bin && \
        find /opt -type f -executable -exec ldd {} \; 2>/dev/null | \
        grep -o '/\(lib\|usr/lib\)[^ ]*\.so[^ ]*' | sort | uniq | \
        xargs -I {} cp --parents {} /deps/


# Minimal stage for per-version CI images (scratch + build artifacts only)
FROM scratch AS artifacts
    # Carry only the built arch's checksums (the builder also copied the
    # committed checksums/build/amd64 from the repo; an arm64 image must not
    # ship them). TARGETARCH is BuildKit's automatic platform arch.
    ARG TARGETARCH
    COPY --from=builder /opt /opt
    COPY --from=builder /deps /deps
    COPY --from=builder /shvr/checksums/build/${TARGETARCH} /shvr/checksums/build/${TARGETARCH}
    CMD ["/nonexistent"]


FROM ${RUNTIME_BASE}

    # Built arch (BuildKit's automatic platform arch), used to scope the bundled
    # checksums to this image's arch.
    ARG TARGETARCH

    # Copy helper script
    COPY "entrypoint.sh" "/opt/shvr/entrypoint.sh"

    # Setup environment
    ENV SHVR_DIR_OUT=/opt

    # Copy built artifacts with preserved metadata for reproducibility
    WORKDIR /
    COPY --from=builder --chown=0:0 "$SHVR_DIR_OUT" "$SHVR_DIR_OUT"
    COPY --from=builder --chown=0:0 /shvr/checksums/build/${TARGETARCH} /opt/shvr/checksums/build/${TARGETARCH}
    COPY --from=builder --chown=0:0 /deps /

    # Generate manifest of all built shells
    RUN find /opt \( -type l -o -type f \) -not -path '*/shvr/*' | sort > /opt/shvr/manifest.txt

    ENTRYPOINT [ "/bin/sh", "/opt/shvr/entrypoint.sh" ]
