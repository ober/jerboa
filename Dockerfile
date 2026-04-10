# Dockerfile — jerboa21/jerboa base image for static binary builds
#
# Provides:
#   - Stock Chez Scheme (glibc) at /usr/local — for compilation steps
#   - Musl Chez Scheme (static) at /build/chez-musl — for linking
#   - Jerboa library source at /build/mine/jerboa/lib
#   - musl-gcc, build-essential, and all linking deps pre-installed
#
# Downstream projects (gitsafe, etc.) use this as their FROM image
# to skip the expensive Chez double-build. They just COPY their source
# and run their musl build script.
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
    file \
    && rm -rf /var/lib/apt/lists/*

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

# ── Copy Jerboa library source ───────────────────────────────────────────────
WORKDIR /build/mine
COPY lib /build/mine/jerboa/lib

# ── Set default environment for downstream builds ───────────────────────────
ENV JERBOA_MUSL_CHEZ_PREFIX=/build/chez-musl
ENV JERBOA_HOME=/build/mine/jerboa

# ── Smoke test ───────────────────────────────────────────────────────────────
RUN scheme --version && \
    musl-gcc --version | head -1 && \
    test -d /build/chez-musl && \
    echo "jerboa21/jerboa base image ready"

WORKDIR /build
CMD ["/bin/bash"]
