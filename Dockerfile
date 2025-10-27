# ISC License
#
# Copyright (c) 2023 Alexandre Gomes Gaigalas <alganet@gmail.com>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

FROM debian:bullseye-slim AS builder

    # Update distro
    RUN apt-get -y update

    # Copy contents
    COPY "shvr.sh" "/shvr/shvr.sh"
    COPY "variants/" "/shvr/variants"
    RUN chmod +x "/shvr/shvr.sh"

    # Setup environment
    ENV SHVR_DIR_SRC "/usr/src/shvr"
    ENV SHVR_DIR_OUT "/opt"
    ARG TARGETS

    # Build
    RUN bash "/shvr/shvr.sh" build $TARGETS

FROM debian:bullseye-slim

    # Setup environment
    ENV SHVR_DIR_OUT /opt

    # Copy built artifacts
    WORKDIR /
    COPY --from=builder "$SHVR_DIR_OUT" "$SHVR_DIR_OUT"