# Dockerfile — jerboa21/jerboa base image for static binary builds
#
# Provides:
#   - Stock Chez Scheme (glibc) at /usr/local — for compilation steps
#   - Musl Chez Scheme (static) at /build/chez-musl — for linking
#   - Jerboa library source at /build/mine/jerboa/lib
#   - jerboa-native-rs source + pre-built libjerboa_native.a (musl)
#   - Rust toolchain with x86_64-unknown-linux-musl target
#   - All common dependency repos cloned under /build/mine/
#   - musl-gcc, build-essential, and all linking deps pre-installed
#
# Downstream projects use this as their FROM image to skip the expensive
# Chez double-build, Rust toolchain install, and repo cloning.
#
# Build & push:
#   make docker-build
#   make docker-push
#
# Or manually:
#   docker build --platform linux/amd64 -t jerboa21/jerboa .
#   docker push jerboa21/jerboa

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# ── System dependencies for static builds ────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    musl-tools \
    musl-dev \
    git \
    ca-certificates \
    curl \
    libncurses-dev \
    uuid-dev \
    liblz4-dev \
    zlib1g-dev \
    libsqlite3-dev \
    pkg-config \
    file \
    && rm -rf /var/lib/apt/lists/*

# musl-tools only provides musl-gcc; Rust cc-rs needs musl-g++ for C++ deps.
# Use system g++ for C++ compilation (it has <sstream> etc. that musl-gcc lacks).
RUN printf '#!/bin/sh\nexec /usr/bin/g++ -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 "$@"\n' \
      > /usr/local/bin/x86_64-linux-musl-g++ && \
    chmod +x /usr/local/bin/x86_64-linux-musl-g++ && \
    ln -sf /usr/local/bin/x86_64-linux-musl-g++ /usr/local/bin/musl-g++

# ── Rust toolchain ────────────────────────────────────────────────────────────
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain stable --profile minimal && \
    . /root/.cargo/env && \
    rustup target add x86_64-unknown-linux-musl

ENV PATH="/root/.cargo/bin:${PATH}"
ENV RUSTUP_HOME="/root/.rustup"

# Set HOME=/build so no real usernames or home directories leak into binaries
ENV HOME=/build
WORKDIR /build

# ── Build Chez Scheme (stock glibc, for compilation steps) ───────────────────
# Installed to /usr/local so `scheme` is on PATH
RUN git clone --depth 1 https://github.com/ober/ChezScheme.git && \
    cd ChezScheme && \
    git submodule update --init --depth 1 && \
    ./configure --threads --disable-x11 --installprefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    cd /build && rm -rf ChezScheme

# ── Build Chez Scheme (musl, for static linking) ────────────────────────────
# Two-pass build:
#   Pass 1: Full build with stock gcc to generate boot files
#   Pass 2: Rebuild kernel only with musl-gcc --static, reusing boot files
# Installed to /build/chez-musl
RUN git clone https://github.com/ober/ChezScheme.git chez-musl-src && \
    cd chez-musl-src && \
    git submodule update --init && \
    ./configure --threads --disable-x11 --installprefix=/build/chez-musl && \
    make -j$(nproc) && \
    cp ta6le/boot/ta6le/petite.boot /tmp/petite.boot && \
    cp ta6le/boot/ta6le/scheme.boot /tmp/scheme.boot && \
    make clean && \
    ./configure --threads --disable-x11 --static CC=musl-gcc --installprefix=/build/chez-musl && \
    mkdir -p ta6le/boot/ta6le && \
    cp /tmp/petite.boot ta6le/boot/ta6le/ && \
    cp /tmp/scheme.boot ta6le/boot/ta6le/ && \
    make -j$(nproc) kernel && \
    make install && \
    cd /build && rm -rf chez-musl-src /tmp/petite.boot /tmp/scheme.boot

# ── Copy Jerboa library + native Rust source ──────────────────────────────────
WORKDIR /build/mine
COPY jerbuild.ss /build/mine/jerboa/jerbuild.ss
COPY lib /build/mine/jerboa/lib
COPY jerboa-native-rs /build/mine/jerboa/jerboa-native-rs

# ── Pre-build libjerboa_native.a (musl, no duckdb) ───────────────────────────
# Warms the Cargo registry cache under /build/.cargo so downstream builds that
# patch regex_native.rs only need to recompile that one module, not fetch crates.
# Uses CARGO_HOME=/build/.cargo so no /root/.cargo paths leak into the .a.
RUN cd /build/mine/jerboa/jerboa-native-rs && \
    grep -q '#\[cfg(feature = "duckdb")\]' src/lib.rs || \
    sed -i 's/^mod duckdb_native;/#[cfg(feature = "duckdb")]\nmod duckdb_native;/' src/lib.rs && \
    CARGO_HOME=/build/.cargo \
    RUSTFLAGS="--remap-path-prefix /build/.cargo/registry/src=crate --remap-path-prefix /build/mine=src" \
    cargo build --release --target x86_64-unknown-linux-musl --no-default-features && \
    strip -S target/x86_64-unknown-linux-musl/release/libjerboa_native.a

# ── Clone all common dependency repos ────────────────────────────────────────
RUN git clone --depth 1 https://github.com/ober/gherkin.git && \
    git clone --depth 1 https://github.com/ober/chez-ssh.git && \
    git clone --depth 1 https://github.com/ober/chez-sqlite.git && \
    git clone --depth 1 https://github.com/ober/chez-crypto.git && \
    git clone --depth 1 https://github.com/ober/chez-ssl.git && \
    git clone --depth 1 https://github.com/ober/chez-https.git && \
    git clone --depth 1 https://github.com/ober/jerboa-awk.git && \
    git clone --depth 1 https://github.com/ober/jerboa-sed.git && \
    git clone --depth 1 https://github.com/ober/jerboa-aws.git && \
    git clone --depth 1 https://github.com/ober/chez-fuse.git

# ── Set default environment for downstream builds ───────────────────────────
ENV JERBOA_MUSL_CHEZ_PREFIX=/build/chez-musl
ENV JERBOA_HOME=/build/mine/jerboa
ENV JERBOA=/build/mine/jerboa/lib
ENV GHERKIN=/build/mine/gherkin/src
ENV AWK_DIR=/build/mine/jerboa-awk/lib
ENV SED_DIR=/build/mine/jerboa-sed/lib
ENV AWS_DIR=/build/mine/jerboa-aws/lib
ENV CHEZ_FUSE_DIR=/build/mine/chez-fuse/lib

# ── Smoke test ───────────────────────────────────────────────────────────────
RUN scheme --version && \
    musl-gcc --version | head -1 && \
    cargo --version && \
    test -d /build/chez-musl && \
    test -f /build/mine/jerboa/jerboa-native-rs/target/x86_64-unknown-linux-musl/release/libjerboa_native.a && \
    echo "jerboa21/jerboa base image ready"

WORKDIR /build
CMD ["/bin/bash"]
