FROM mt798x-builder:24.04
# 6.12 树构建所需的环境与工具固化
ENV FORCE_UNSAFE_CONFIGURE=1
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    python3 libzstd-dev cpio qemu-system-arm \
    && rm -rf /var/lib/apt/lists/*
