# 360t7m-immortalwrt-slim — 360T7M（MT7981B）自编译固件工作区
#   mt798x-6.6  = 稳定基线（ImmortalWrt 24.10 / 内核 6.6.133 / mt_wifi 7.6.6.1）
#   mt798x-6.12 = 新线   （ImmortalWrt 25.12 / 内核 6.12.103 / mtkhnat）
set shell := ["bash", "-c"]

img  := "mt798x-builder:24.04-v4"
# 编译并行度：核多时留 4 核给宿主（14 核 → 10），少核机器（含 CI 的 4 vCPU
# ubuntu-24.04 runner）则用满，避免在 CI 上退化成 -j1。
# 想显式指定：`JOBS=$(nproc) just build66`。
jobs := env("JOBS", `echo $(( $(nproc) > 8 ? $(nproc) - 4 : $(nproc) ))`)
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
            #
            # 每次构建都用种子覆盖 .config：种子是唯一事实来源，.config 是派生物。
            # 否则改完种子在本机重建会沿用旧 .config，产物哈希与 CI（干净克隆、
            # 无 .config）不一致 —— 而「清洁克隆可复现」是本仓库的核心不变量。
            if [ ! -d feeds/luci ]; then
                ./scripts/feeds update -a
                ./scripts/feeds install -a
            fi
            cp defconfig/360t7-slim.config .config
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

[doc("QEMU 冒烟：在 qemu virt 上真启动固件（内核+完整 rootfs），核验配置真生效。会先 distclean 再用 env/kernel-config 重建内核，产物哈希偏离出厂值；要拿回请再 just build<树>")]
vm-smoke tree:
    tools/qemu-smoke.sh {{tree}}

[doc("QEMU 冒烟：6.6 稳定基线")]
vm-smoke66:
    @just vm-smoke mt798x-6.6

[doc("QEMU 冒烟：6.12 新线")]
vm-smoke612:
    @just vm-smoke mt798x-6.12

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

[doc("清理指定树构建产物（保留工具链/dl 缓存/固件产物；要完全复现干净克隆的哈希需连工具链一并清，见 distclean）")]
clean tree:
    docker run --rm -v {{root}}/{{tree}}:/build -w /build {{img}} rm -rf build_dir tmp logs

[doc("彻底清理指定树：连 staging_dir（工具链）与派生的 .config 一起删。用于复现干净克隆 / CI 的产物哈希")]
distclean tree:
    docker run --rm -v {{root}}/{{tree}}:/build -w /build {{img}} rm -rf build_dir tmp logs staging_dir .config .config.old

[doc("彻底清理 6.6")]
distclean66:
    @just distclean mt798x-6.6

[doc("彻底清理 6.12")]
distclean612:
    @just distclean mt798x-6.12

[doc("清理 6.6 构建产物")]
clean66:
    @just clean mt798x-6.6

[doc("清理 6.12 构建产物")]
clean612:
    @just clean mt798x-6.12

[doc("取/更新 U-Boot 源码（hanwckf/bl-mt798x，按 uboot-revision 固定 commit）")]
uboot-fetch:
    #!/usr/bin/env bash
    set -euo pipefail
    rev="$(tr -d '[:space:]' < {{root}}/uboot-revision)"
    [ -n "$rev" ] || { echo "uboot-revision 为空" >&2; exit 1; }
    d={{root}}/bl-mt798x
    if [ ! -d "$d/.git" ]; then
        git clone --filter=blob:none https://github.com/hanwckf/bl-mt798x "$d"
    else
        git -C "$d" fetch --all --tags --quiet
    fi
    git -C "$d" -c advice.detachedHead=false checkout --quiet "$rev"
    echo "bl-mt798x @ $(git -C "$d" rev-parse --short=8 HEAD)（$rev）"

[doc("构建 U-Boot + ATF（hanwckf/bl-mt798x，SOC=mt7981 BOARD=360t7），产物复制到 out/")]
uboot:
    #!/usr/bin/env bash
    set -euo pipefail
    just uboot-fetch
    docker run --rm -v {{root}}/bl-mt798x:/bl -w /bl {{img}} \
        bash -euo pipefail -c '
            # ATF 的 makeconfig 找的是 `python` 而非 `python3`；缺它时
            # defconfig 静默不生效，平台回落到 fvp，最后报 fip build fail。
            # 只在本配方内补软链，不动构建器镜像（固件构建不受影响）。
            command -v python >/dev/null 2>&1 ||
                ln -sf "$(command -v python3)" /usr/local/bin/python
            exec env SOC=mt7981 BOARD=360t7 ./build.sh
        '
    out={{root}}/out
    mkdir -p "$out"
    cp -v {{root}}/bl-mt798x/output/mt7981_360t7-* "$out/"
    ( cd "$out" && sha256sum mt7981_360t7-* )

[doc("只列出 U-Boot 构建会产出的文件（不构建）")]
uboot-status:
    @echo "固定 commit: $(cat {{root}}/uboot-revision)"
    @echo "本地状态  : $(git -C {{root}}/bl-mt798x rev-parse --short=8 HEAD 2>/dev/null || echo '未取源码（just uboot-fetch）')"

[doc("重建 docker 构建器镜像（自包含，FROM ubuntu:24.04）")]
builder:
    docker build -t {{img}} -f {{root}}/docker/Dockerfile.builder {{root}}/docker
