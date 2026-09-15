# 360T7M 固件构建器镜像（自包含）
# 原 mt798x-builder:24.04 是无出处的本地镜像，本文件按其 docker history 完整还原：
# ubuntu:24.04 + OpenWrt/ImmortalWrt 宿主编译依赖，并合并 v2 增量层
# （libzstd-dev / qemu-system-arm / FORCE_UNSAFE_CONFIGURE）。
# 重建：just builder（产出 mt798x-builder:24.04-v4）
#
# v4 增量：gcc-aarch64-linux-gnu / libgnutls28-dev / uuid-dev。
# 前者是 hanwckf/bl-mt798x（ATF + U-Boot）官方要求的交叉编译器
# （其 build.sh 硬编码 TOOLCHAIN=aarch64-linux-gnu-），
# 后两者是 ATF 20240117 的构建依赖。见 justfile 的 uboot 配方。
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    FORCE_UNSAFE_CONFIGURE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf automake autopoint bc binutils bison build-essential \
        ca-certificates cpio curl device-tree-compiler fakeroot file flex gawk \
        gcc-aarch64-linux-gnu libgnutls28-dev uuid-dev \
        git libelf-dev libgmp-dev libltdl-dev libmpc-dev libmpfr-dev \
        libncurses-dev libssl-dev libtool libzstd-dev lz4 lzop m4 make patch \
        pkg-config python3 python3-pip python3-ply python3-pyelftools \
        python3-setuptools qemu-system-arm quilt rsync swig unzip wget xxd \
        xz-utils zip zlib1g-dev zstd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

CMD ["/bin/bash"]
