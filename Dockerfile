# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

# Pinned 2026-03-06 for reproducible builds
FROM debian:trixie-slim@sha256:1d3c811171a08a5adaa4a163fbafd96b61b87aa871bbc7aa15431ac275d3d430 AS toolchain

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


FROM busybox:stable-musl

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
