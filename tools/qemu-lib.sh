#!/usr/bin/env bash
# 360T7M 固件在 QEMU 上启动的公共部分：构建（带调试内核符号）、
# 从 FIT 抽 initrd、重打包。被 qemu-smoke.sh / qemu-webui.sh source。
#
# 为什么需要这一整套：MT7981 没有 QEMU 机型，宿主的 qemu-system-aarch64
# 只能用通用 `virt` 机型，所以必须给内核补 PL011 串口 / virtio 等调试符号。
# 相关踩坑都写在下面各函数的注释里，改动前先读。
#
# 约定：下面所有函数都收 <root>（仓库根）与 <tree>（如 mt798x-6.12）两个绝对路径。

export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/1000/docker.sock}"

# 并行度：核多时留 4 核给宿主（14 核 → 10），≤ 8 核用满（否则 CI 的 4 vCPU
# runner 会退化成 -j1）。JOBS 可覆盖，与 justfile 同规则。
qemu_jobs() { echo $(( $(nproc) > 8 ? $(nproc) - 4 : $(nproc) )); }

# 写调试符号到 <tree>/env/kernel-config。
# 该文件由 include/target.mk 的 LINUX_KCONFIG_LIST 最后引入 → 合并优先级最高，
# 且 /env 已 gitignore，所以不动提交的 filogic/config-*，出厂哈希不受影响。
#
# 关于 DEVTMPFS（别再试了）：initramfs 里 /dev 是空目录，但**不影响**启动 ——
# 内核给 rdinit 的 fd 0/1/2 直接接在 console 驱动上，用户态写 stdout 不经过
# /dev/console。而且它也打不开：Kernel/Configure/Default 会把顶层 .config 的
# CONFIG_KERNEL_* 去前缀后**追加**在 kconfig 合并结果之后，种子里那句
# `# CONFIG_KERNEL_DEVTMPFS is not set` 会覆盖 env；改成直接动顶层 .config
# 又会让构建系统报 "your configuration is out of sync"。
qemu_debug_env_text() {
    cat <<'EOF'
# 仅用于 QEMU virt 启动的调试内核符号，勿提交（/env 已 gitignore）
CONFIG_SERIAL_AMBA_PL011=y
CONFIG_SERIAL_AMBA_PL011_CONSOLE=y
CONFIG_RTC_DRV_PL031=y
CONFIG_VIRTIO=y
CONFIG_VIRTIO_MENU=y
CONFIG_VIRTIO_MMIO=y
CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_BLK_DEV_INITRD=y
# 6.12 比 6.6 多出的两个符号，且都 `depends on VIRTIO`：env 打开 VIRTIO 后
# 它们才第一次可见，非交互的 syncconfig 会为 (NEW) 去读 stdin 然后失败
# （现象：world Error 1，日志里只有一行 syncconfig）。默认值都是 n，
# 这里显式写死（写死的是默认值，不改变出厂内核）。
# CONFIG_NSM is not set
# CONFIG_VIRTIO_DEBUG is not set
EOF
}

qemu_write_debug_env() { # <tree>
    mkdir -p "$1/env"
    qemu_debug_env_text > "$1/env/kernel-config"
}

# distclean + world。
#   distclean 必须先做：env 会改内核 vermagic/包哈希，而 build_dir 里上一轮
#   编好的 kmod-*.ipk 仍带旧哈希，package/install 会报
#   "cannot find dependency kernel (= <hash>)"（并行构建下只有一行光秃秃的
#   "make -r world: build failed"，要用 -j1 V=s 才现形）。
#   `-i </dev/null` 也必须：6.12 内核有 (NEW) 符号，syncconfig 会去读 stdin，
#   拿不到 EOF 时它会尝试打开 TTY 并直接失败。
# 走 world 而不是 target/linux/compile：后者不产出 bin/targets 下的 initramfs
# 产物，而 initrd 必须从那个 FIT 里抽。
qemu_build_debug() { # <tree>
    local jobs; jobs="$(qemu_jobs)"
    docker run --rm -v "$1":/build -w /build "${IMG:-mt798x-builder:24.04-v4}" \
        rm -rf build_dir tmp logs staging_dir .config .config.old
    docker run --rm -i -v "$1":/build -w /build "${IMG:-mt798x-builder:24.04-v4}" \
        bash -euo pipefail -c '
            ./scripts/feeds update -a >/dev/null 2>&1 || true
            ./scripts/feeds install -a >/dev/null 2>&1 || true
            cp defconfig/360t7-slim.config .config
            exec make -j'"$jobs"' REVISION="$(tr -d "[:space:]" < revision)" world
        ' </dev/null >/dev/null
}

# 两树的 initramfs 产物名不同：6.6 是 initramfs-kernel.bin，6.12 是
# initramfs-recovery.itb（同为 FIT，内含 kernel/initrd/fdt 三个节点）。
# 注意别用 `ls A B`：某个 glob 不匹配时 ls 返回 2，配合 set -e/pipefail 会让
# 整个赋值直接退出（现象：只打印首行 banner 就 rc=2，连报错都来不及输出）。
qemu_find_fit() { # <tree> → 打印 FIT 绝对路径
    local f
    for f in "$1"/bin/targets/mediatek/filogic/*initramfs-kernel.bin \
             "$1"/bin/targets/mediatek/filogic/*initramfs-recovery.itb; do
        [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
    done
    return 1
}

qemu_find_kimage() { # <tree> → 打印内核 Image 绝对路径
    local kd
    kd="$(ls -d "$1"/build_dir/target-*/linux-*/linux-*/ | head -1)"
    printf '%s\n' "${kd%/}/arch/arm64/boot/Image"
}

# 从 FIT 的 initrd-1 节点按偏移抽出 xz 流（手写 FDT 遍历，不依赖 libfdt）。
# 路径处理与已验证的 smoke 一致：把 <root> 挂成 /repo，再传相对路径。
qemu_extract_initrd() { # <root> <fit-abs> <workdir>
    local root="$1" fit="$2" work="$3"
    docker run --rm -v "$root":/repo -v "$work":/work -w /work "${IMG:-mt798x-builder:24.04-v4}" \
        bash -euo pipefail -c '
            python3 - "$1" /work <<"PY"
import sys, struct, os
fit, outdir = sys.argv[1], sys.argv[2]
d = open(fit, "rb").read()
magic, size, off_struct, off_str, off_rsv, ver, lastc, cpu, sz_str, sz_struct = struct.unpack(">10I", d[:40])
if magic != 0xd00dfeed:
    sys.exit(f"不是 FDT/FIT: magic=0x{magic:08x}")
def cstr(off):
    return d[off:d.index(b"\0", off)].decode("latin1")
q, stack = off_struct, []
while q < off_struct + sz_struct:
    tok, = struct.unpack(">I", d[q:q+4])
    if tok == 1:
        nm = cstr(q+4); stack.append(nm or "<root>"); q = (q+4+len(nm)+1+3) & ~3
    elif tok == 2:
        stack.pop(); q += 4
    elif tok == 3:
        ln, nmoff = struct.unpack(">II", d[q+4:q+12]); name = cstr(off_str+nmoff); vp = q+12
        if name == "data" and stack[-1].startswith("initrd"):
            open(os.path.join(outdir, "initrd.cpio.xz"), "wb").write(d[vp:vp+ln])
            print(f"   initrd: {ln} bytes @file+{vp}")
        q = (vp+ln+3) & ~3
    elif tok == 4:
        q += 4
    else:
        break
PY
        ' -- "/repo/${fit#"$root"/}"
}

# 解包 initrd → 禁用 vendor MTK 模块自加载 → 以 CRC32、单流重打包成
# <workdir>/initrd-run.cpio.xz。
#   vendor 模块必须禁：无 MT7981 寄存器时 conninfra 会 NULL 解引用 panic
#   （consys_hw_pwr_on+0x1c/0x274 [conninfra] + msg_thread_deinit）。
#   必须 xz --check=crc32 且单流：本树内核只编了 CRC32（CONFIG_XZ_DEC_CRC64
#   缺席），默认 CRC64 与 -T0 多块流会被内核解码器**静默**拒绝（现象：
#   Freeing initrd memory 之后直接 panic "Unable to mount root fs"，
#   看不到 Run /init）。
qemu_repack_initrd() { # <workdir>
    docker run --rm -v "$1":/work -w /work "${IMG:-mt798x-builder:24.04-v4}" bash -euo pipefail -c '
        mkdir -p irx && cd irx && xz -dc ../initrd.cpio.xz | cpio -idm --quiet 2>/dev/null
        mkdir -p ../disabled
        for d in etc/modules-boot.d etc/modules.d; do
          [ -d "$d" ] || continue
          for f in "$d"/*; do
            [ -f "$f" ] || continue
            if grep -qE "conninfra|mt_wifi|mtk_warp|mtkhnat|warp|mtk_|mediatek" "$f" 2>/dev/null; then
              mv "$f" "../disabled/$(echo $d | tr / _)_$(basename $f)"
            fi
          done
        done
        echo "   已禁用 vendor 模块自加载: $(ls ../disabled | tr "\n" " ")"
        find . | cpio -o -H newc --quiet 2>/dev/null > ../smoke.cpio
        xz -9 --check=crc32 -c ../smoke.cpio > ../initrd-run.cpio.xz
        xz -l ../initrd-run.cpio.xz
    '
}

# ---- 调试产物缓存 ----------------------------------------------------------
# 出厂内核既没有 PL011 串口也没有 virtio，在 QEMU virt 上连串口输出和网卡都
# 没有，所以跑 QEMU 绕不开「换一个带调试符号的内核」这个前提。
# 但**不必每次重建**：把产物缓存到 <tree>/.qemu-cache/<key>/，命中就直接用。
# 两个好处：一是首次之外几乎零成本；二是 build_dir 不被弄脏 —— 出厂产物哈希
# 保持不变，不用再「跑完重编复原」。
# key 覆盖会影响产物的全部输入：内核版本(revision) + 种子 + 调试符号 + feeds 固定点。
# 强制重建：FORCE_BUILD=1
qemu_cache_key() { # <tree>
    {
        cat "$1/revision"
        cat "$1/defconfig/360t7-slim.config"
        qemu_debug_env_text
        cat "$1/feeds.conf.default"
    } | md5sum | cut -d' ' -f1
}

# 在 $work 下备好 Image 与 initrd.cpio.xz（必要时才构建）
qemu_ensure_artifacts() { # <root> <tree> <work>
    local root="$1" tree="$2" work="$3"
    local dir="$tree/.qemu-cache/$(qemu_cache_key "$tree")"
    if [ "${FORCE_BUILD:-0}" != 1 ] && [ -f "$dir/Image" ] && [ -f "$dir/initrd.cpio.xz" ]; then
        echo "   命中缓存：$dir"
        cp "$dir/Image" "$dir/initrd.cpio.xz" "$work/"
        return 0
    fi
    echo "   缓存未命中 → 构建带调试符号的内核（world，约 20 分钟；之后复用）"
    qemu_write_debug_env "$tree"
    QEMU_ENV_WRITTEN=1
    qemu_build_debug "$tree"
    local fit image
    fit="$(qemu_find_fit "$tree")" || { echo "没找到 initramfs 的 FIT 产物" >&2; return 1; }
    image="$(qemu_find_kimage "$tree")"
    qemu_extract_initrd "$root" "$fit" "$work"
    mkdir -p "$dir"
    cp "$image" "$dir/Image"
    cp "$work/initrd.cpio.xz" "$dir/initrd.cpio.xz"
    cp "$image" "$work/Image"
    echo "   已写入缓存：$dir"
}
