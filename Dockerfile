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

    # Update distro
    RUN apt-get -y update

    # Copy only musl-cross-make dependencies for maximum cacheability
    COPY "build/musl-cross-make-*" "/usr/src/shvr/"
    COPY "checksums/sources/musl-cross-make-*" "/shvr/checksums/sources/"
    COPY "common/musl-cross-make.sh" "/shvr/common/musl-cross-make.sh"

    COPY "shvr.sh" "/shvr/shvr.sh"
    RUN chmod +x "/shvr/shvr.sh"

    # Setup environment
    ENV SHVR_DIR_SRC="/usr/src/shvr"
    ENV SHVR_DIR_OUT="/opt"

    # Build musl cross-compiler once (shared by all static variants)
    RUN bash "/shvr/shvr.sh" musl-build

    # Pre-install Rust toolchain (used by brush and yashrs)
    COPY "build/rustup-init-*" "/usr/src/shvr/"
    COPY "checksums/sources/rustup-init-*" "/shvr/checksums/sources/"
    RUN sh "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh" -y && \
        . "$HOME/.cargo/env" && \
        rustup target add x86_64-unknown-linux-musl


FROM toolchain AS builder

    # Copy contents
    COPY "build/" "/usr/src/shvr"
    COPY "checksums/" "/shvr/checksums"
    COPY "common/" "/shvr/common"
    COPY "patches/" "/shvr/patches"
    COPY "variants/" "/shvr/variants"

    ARG TARGETS

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
    COPY --from=builder /opt /opt
    COPY --from=builder /deps /deps
    COPY --from=builder /shvr/checksums/build /shvr/checksums/build
    CMD ["/nonexistent"]


FROM ${RUNTIME_BASE}

    # Copy helper script
    COPY "entrypoint.sh" "/opt/shvr/entrypoint.sh"

    # Setup environment
    ENV SHVR_DIR_OUT=/opt

    # Copy built artifacts with preserved metadata for reproducibility
    WORKDIR /
    COPY --from=builder --chown=0:0 "$SHVR_DIR_OUT" "$SHVR_DIR_OUT"
    COPY --from=builder --chown=0:0 /shvr/checksums/build /opt/shvr/checksums/build
    COPY --from=builder --chown=0:0 /deps /

    # Generate manifest of all built shells
    RUN find /opt \( -type l -o -type f \) -not -path '*/shvr/*' | sort > /opt/shvr/manifest.txt

    ENTRYPOINT [ "/bin/sh", "/opt/shvr/entrypoint.sh" ]
