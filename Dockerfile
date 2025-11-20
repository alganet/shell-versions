# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: ISC

FROM debian:bookworm-slim AS builder

    # Update distro
    RUN apt-get -y update

    # Copy contents
    COPY "shvr.sh" "/shvr/shvr.sh"
    COPY "variants/" "/shvr/variants"
    COPY "common/" "/shvr/common"
    COPY "patches/" "/shvr/patches"
    COPY "build/" "/usr/src/shvr"
    RUN chmod +x "/shvr/shvr.sh"

    # Setup environment
    ENV SHVR_DIR_SRC="/usr/src/shvr"
    ENV SHVR_DIR_OUT="/opt"
    ARG TARGETS

    # Build
    RUN bash "/shvr/shvr.sh" build $TARGETS

    # Extract unique library dependencies
    RUN mkdir -p /deps/bin && \
        find /opt -type f -executable -exec ldd {} \; 2>/dev/null | \
        grep -o '/\(lib\|usr/lib\)[^ ]*\.so[^ ]*' | sort | uniq | \
        xargs -I {} cp --parents {} /deps/

    RUN mkdir -p /deps/opt/shvr && \
        find /opt \( -type l -o -type f \) | sort -t'_' -k1,1 -k2Vr > /deps/opt/shvr/manifest.txt

    # Find first shell in TARGETS and symlink it to /deps/bin/sh
    RUN first_shell=$(echo $TARGETS | cut -d' ' -f1) && \
        first_shell_opt_path=$(find /opt -type d -name "$first_shell*" | head -n1) && \
        first_shell_executable=$(find "$first_shell_opt_path" -type f -executable | head -n1) && \
        ln -s "$first_shell_executable" /deps/bin/sh

FROM scratch

    # Copy helper script
    COPY "entrypoint.sh" "entrypoint.sh"

    # Setup environment
    ENV SHVR_DIR_OUT=/opt

    # Copy built artifacts
    WORKDIR /
    COPY --from=builder "$SHVR_DIR_OUT" "$SHVR_DIR_OUT"
    COPY --from=builder /deps /

    ENTRYPOINT [ "/bin/sh", "entrypoint.sh" ]
