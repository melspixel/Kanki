FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       binutils ca-certificates coreutils curl e2fsprogs file findutils \
       gcc git grep gzip libarchive-dev make nettle-dev pkg-config python3 \
       qemu-user-static sed squashfs-tools tar zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

CMD ["bash", "tools/audit_pw6_rootfs.sh"]
