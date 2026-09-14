# 360T7M 固件工作区
#   mt798x-6.6  = 稳定基线（ImmortalWrt 24.10 / 内核 6.6.133 / mt_wifi 7.6.6.1）
#   mt798x-6.12 = 新线   （ImmortalWrt 25.12 / 内核 6.12.103 / mtkhnat）
set shell := ["bash", "-c"]

img  := "mt798x-builder:24.04-v2"
jobs := `nproc`
root := justfile_directory()

# 列出所有配方
default:
    @just --list

[doc("在指定树执行 make 目标（默认 world 全量构建）")]
build tree *args="world":
    docker run --rm -v {{root}}/{{tree}}:/build -w /build {{img}} make -j{{jobs}} {{args}}

[doc("6.6 稳定基线：全量构建（默认）")]
build66 *args="world":
    @just build mt798x-6.6 {{args}}

[doc("6.12 新线：全量构建（默认）")]
build612 *args="world":
    @just build mt798x-6.12 {{args}}

[doc("冒烟：6.6 仅编译 dnsmasq 验证工具链")]
smoke66:
    @just build mt798x-6.6 "package/network/services/dnsmasq/clean package/network/services/dnsmasq/compile"

[doc("冒烟：6.12 增量校验（全缓存应秒过）")]
smoke612:
    @just build mt798x-6.12 "world"

[doc("清理指定树构建产物（保留工具链/dl 缓存/固件产物）")]
clean tree:
    rm -rf {{root}}/{{tree}}/build_dir {{root}}/{{tree}}/tmp {{root}}/{{tree}}/logs

[doc("重建 docker 构建器镜像")]
builder:
    docker build -t {{img}} -f docker/Dockerfile.builder {{root}}
