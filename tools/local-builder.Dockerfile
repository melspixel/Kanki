FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_VERSION=1.92.0

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl clang cmake ninja-build pkg-config protobuf-compiler \
       python3 perl make git gcc g++ file binutils zip unzip zstd xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "$RUSTUP_HOME" "$CARGO_HOME" \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
       | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "$RUST_VERSION" \
    && rustup target add armv7-unknown-linux-gnueabihf \
    && rustc --version \
    && cargo --version \
    && protoc --version \
    && chmod -R a+rX "$RUSTUP_HOME" "$CARGO_HOME"

WORKDIR /work

CMD ["bash", "tools/build_kindle_package.sh"]
