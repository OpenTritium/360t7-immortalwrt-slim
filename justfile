# 360t7m-immortalwrt-slim — 360T7M（MT7981B）自编译固件工作区
#   mt798x-6.6  = 稳定基线（ImmortalWrt 24.10 / 内核 6.6.133 / mt_wifi 7.6.6.1）
#   mt798x-6.12 = 新线   （ImmortalWrt 25.12 / 内核 6.12.103 / mtkhnat）
set shell := ["bash", "-c"]

img  := "mt798x-builder:24.04-v3"
jobs := `nproc`
root := justfile_directory()

# 列出所有配方
default:
    @just --list

[doc("在指定树执行 make 目标（默认 world 全量构建）")]
build tree *args="world":
    #!/usr/bin/env bash
    set -euo pipefail
    revfile="{{root}}/{{tree}}/revision"
    [ -f "$revfile" ] || { echo "缺少 $revfile（该文件入库，勿删）" >&2; exit 1; }
    rev="$(tr -d '[:space:]' < "$revfile")"
    [ -n "$rev" ] || { echo "$revfile 为空" >&2; exit 1; }
    docker run --rm -v {{root}}/{{tree}}:/build -w /build {{img}} \
        bash -euo pipefail -c '
            # 顺序不能变，且 .config 必须在 feeds 之后才出现：
            # scripts/feeds 的 refresh_config()（feeds 脚本 line 878，由
            # 「feeds update」结尾调用）在发现 .config 存在时会执行
            # `make defconfig`，而此刻 package/feeds/* 符号链接尚未建立，
            # 于是 feed 里的包全被当成不存在，.config 被抹掉数千行
            # （现象：后续 package/install 报 cannot find dependency luci）。
            # 上游的守卫是「新克隆没有 .config 就直接返回」，所以这里
            # 不能事先放 .config —— 种子文件放在 defconfig/ 下，feeds 就绪后再注入。
            if [ ! -d feeds/luci ]; then
                ./scripts/feeds update -a
                ./scripts/feeds install -a
            fi
            [ -f .config ] || cp defconfig/360t7-slim.config .config
            exec make -j'"{{jobs}}"' REVISION="'"$rev"'" {{args}}
        '

[doc("6.6 稳定基线：全量构建（默认）")]
build66 *args="world":
    @just build mt798x-6.6 {{args}}

[doc("6.12 新线：全量构建（默认）")]
build612 *args="world":
    @just build mt798x-6.12 {{args}}

[doc("冒烟：在指定树全新编译 dnsmasq（验证工具链 + 热路径编译参数）")]
smoke tree:
    @just build {{tree}} "package/network/services/dnsmasq/clean package/network/services/dnsmasq/compile"

[doc("冒烟：6.6 稳定基线")]
smoke66:
    @just smoke mt798x-6.6

[doc("冒烟：6.12 新线")]
smoke612:
    @just smoke mt798x-6.12

[doc("按格式取产物复制到 out/ 并打印 sha256：just pick <tree> <sysupgrade|initramfs|all>")]
pick tree format="sysupgrade":
    #!/usr/bin/env bash
    set -euo pipefail
    src="{{root}}/{{tree}}/bin/targets/mediatek/filogic"
    out="{{root}}/out"
    mkdir -p "$out"
    shopt -s nullglob
    case "{{format}}" in
        sysupgrade) p=("$src"/*sysupgrade*.bin "$src"/*sysupgrade*.itb) ;;
        initramfs)  p=("$src"/*initramfs*.bin "$src"/*initramfs*.itb) ;;
        all)        p=("$src"/*sysupgrade*.bin "$src"/*sysupgrade*.itb "$src"/*initramfs*.bin "$src"/*initramfs*.itb) ;;
        *) echo "未知格式：{{format}}（可用 sysupgrade / initramfs / all）" >&2; exit 1 ;;
    esac
    (( ${#p[@]} )) || { echo "无产物，请先 just build{{tree}}" >&2; exit 1; }
    for f in "${p[@]}"; do cp -u "$f" "$out/"; done
    ( cd "$out" && for f in "${p[@]}"; do sha256sum "$(basename "$f")"; done )

[doc("取 6.6 产物（默认 sysupgrade）")]
pick66 format="sysupgrade":
    @just pick mt798x-6.6 {{format}}

[doc("取 6.12 产物（默认 sysupgrade）")]
pick612 format="sysupgrade":
    @just pick mt798x-6.12 {{format}}

[doc("清理指定树构建产物（容器内执行，可删 root 属主残留；保留工具链/dl 缓存/固件产物）")]
clean tree:
    docker run --rm -v {{root}}/{{tree}}:/build -w /build {{img}} rm -rf build_dir tmp logs

[doc("清理 6.6 构建产物")]
clean66:
    @just clean mt798x-6.6

[doc("清理 6.12 构建产物")]
clean612:
    @just clean mt798x-6.12

[doc("重建 docker 构建器镜像（自包含，FROM ubuntu:24.04）")]
builder:
    docker build -t {{img}} -f {{root}}/docker/Dockerfile.builder {{root}}/docker
