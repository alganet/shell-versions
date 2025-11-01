# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

FROM debian:bookworm-slim AS builder

    # Update distro
    RUN apt-get -y update

    # Copy contents
    COPY "shvr.sh" "/shvr/shvr.sh"
    COPY "variants/" "/shvr/variants"
    COPY "build/" "/usr/src/shvr"
    RUN chmod +x "/shvr/shvr.sh"

    # Setup environment
    ENV SHVR_DIR_SRC="/usr/src/shvr"
    ENV SHVR_DIR_OUT="/opt"
    ARG TARGETS

    # Build
    RUN bash "/shvr/shvr.sh" build $TARGETS

FROM debian:bookworm-slim

    # Setup environment
    ENV SHVR_DIR_OUT=/opt

    # Copy built artifacts
    WORKDIR /
    COPY --from=builder "$SHVR_DIR_OUT" "$SHVR_DIR_OUT"