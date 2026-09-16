#!/usr/bin/env bash
# QEMU 冒烟：把真实固件（内核 + 完整 rootfs）在 qemu-system-aarch64 的 `virt`
# 机型上真启动，核验「内核能起 + 用户态能引导 + 关键配置真生效」。
#
# 为什么需要：本仓库既有的验证口径是静态的（ELF NEEDED 闭包、包清单、产物哈希），
# 因为 MT7981 没有 QEMU 机型。但静态核验查不出「配置写了没生效」这类问题
# （第九轮那个 fq pacing / BBR 覆盖 bug 就是这么漏过去的）。本脚本用
# qemu 通用机型启动真实 rootfs，覆盖「内核引导 + 用户态 preinit/procd +
# UCI 配置落盘」这一段；MTK WiFi/HNAT/NAND 等硬件路径仍无法覆盖。
#
# 用法：tools/qemu-smoke.sh <tree>     例：tools/qemu-smoke.sh mt798x-6.6
# 依赖：mt798x-builder:24.04-v4 镜像（含 qemu-system-aarch64）
#
# 原理要点（踩过的坑，勿改）：
#  1) 调试符号写 <tree>/env/kernel-config：该文件由 include/target.mk 的
#     LINUX_KCONFIG_LIST 最后引入 → 合并优先级最高，且 /env 已 gitignore，
#     不改提交的 filogic/config-*，出厂内核与 README 哈希不受影响。
#  2) INITRAMFS 不是内建（CONFIG_INITRAMFS_SOURCE 为空），它作为 FIT 的
#     initrd-1 节点、**xz 压缩**存在。必须从 FIT 里按偏移抽出来喂给 -initrd。
#  3) 重打包 initrd 时必须 `xz --check=crc32` 且单流：本树内核只编了
#     CRC32（CONFIG_XZ_DEC_CRC64 缺席），默认的 CRC64 与 `-T0` 多块流
#     都会被内核解码器静默拒绝（现象：Freeing initrd memory 之后直接
#     panic "Unable to mount root fs"，看不到 Run /init）。
#  4) 不要试图开 DEVTMPFS。initramfs 里 /dev 确实是空目录（实测 cpio 内无任何
#     设备节点），但**不影响**：内核给 rdinit 的 fd 0/1/2 直接接在 console 驱动上，
#     用户态往 stdout 写不经过 /dev/console，procd 也照常起。本冒烟在
#     CONFIG_DEVTMPFS is not set 的内核上全项通过即为证。
#     另：DEVTMPFS 也**不能**通过 env/kernel-config 打开 ——
#     Kernel/Configure/Default 会把顶层 .config 的 CONFIG_KERNEL_* 去前缀后追加到
#     .config.target（位于 kconfig 合并结果之后），种子里的
#     `# CONFIG_KERNEL_DEVTMPFS is not set` 会把它覆盖掉；而直接改顶层 .config 又会
#     让构建系统报 "your configuration is out of sync"。两头都堵，且无必要。
#  5) 必须禁用 vendor MTK 模块自加载（conninfra / mt_wifi / mtk_warp /
#     mtkhnat），否则 conninfra 在无 MT7981 寄存器的情况下 NULL 解引用
#     直接 panic。这些模块与「内核引导 + 用户态」无关，禁掉不影响验收。
set -euo pipefail

tree="${1:?用法: qemu-smoke.sh <tree>（例 mt798x-6.6）}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
img="${IMG:-mt798x-builder:24.04-v4}"
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/1000/docker.sock}"

[ -d "$root/$tree" ] || { echo "没有 $tree 目录" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ---- 1. 调试内核配置（不入库：/env 在 .gitignore） ----
mkdir -p "$root/$tree/env"
cat > "$root/$tree/env/kernel-config" <<'EOF'
# 仅用于 QEMU virt 冒烟的调试内核符号，勿提交（/env 已 gitignore）
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
# 它们才第一次可见，非交互的 syncconfig 会为 (NEW) 去读 stdin 然后失败。
# 默认值都是 n，这里显式写死（写死的是默认值，不改变出厂内核）。
# CONFIG_NSM is not set
# CONFIG_VIRTIO_DEBUG is not set
EOF
cleanup_env() { rm -rf "$root/$tree/env"; }
trap 'cleanup_env; rm -rf "$work"' EXIT

echo "== [1/4] 用调试符号重建（内核 + 镜像；不碰出厂 defconfig）=="
# 必须走 world：只编 target/linux/compile 不会产出 bin/targets 下的
# initramfs-kernel.bin（FIT），而 initrd 必须从那个 FIT 里抽。
# `-i </dev/null` 也必须：6.12 内核有大量 (NEW) 符号，syncconfig 会去读 stdin，
# 拿不到 EOF 时它会尝试打开 TTY 并直接失败（现象：world Error 1，无具体报错）。
# 必须先 distclean：env/kernel-config 会改内核 vermagic/包哈希，而 build_dir 里
# 上一轮编好的 kmod-*.ipk 仍带着旧哈希，package/install 阶段会报
# "cannot find dependency kernel (= <hash>)"（现象：并行构建下只有一行
# "make -r world: build failed"，看不出原因）。distclean 只删
# build_dir/tmp/logs/staging_dir/.config，dl/ 缓存保留。
docker run --rm -v "$root/$tree":/build -w /build "$img" \
    rm -rf build_dir tmp logs staging_dir .config .config.old
# 并行度同样留 4 核给宿主（JOBS 可覆盖，与 justfile 一致）。
JOBS="${JOBS:-$(echo $(( $(nproc) > 4 ? $(nproc) - 4 : 1 )))}"
docker run --rm -i -v "$root/$tree":/build -w /build "$img" \
    bash -euo pipefail -c '
        ./scripts/feeds update -a >/dev/null 2>&1 || true
        ./scripts/feeds install -a >/dev/null 2>&1 || true
        cp defconfig/360t7-slim.config .config
        exec make -j'"$JOBS"' REVISION="$(tr -d "[:space:]" < revision)" world
    ' </dev/null >/dev/null

# 两树的 initramfs 产物名不同：6.6 是 initramfs-kernel.bin，6.12 是
# initramfs-recovery.itb（同为 FIT，内含 kernel/initrd/fdt 三个节点）。
# 注意别用 `ls A B`：某个 glob 不匹配时 ls 返回 2，配合 set -e/pipefail 会让
# 整个赋值直接退出（现象：只打印 [1/4] 就 rc=2，连下面的报错都来不及输出）。
FIT=""
for f in "$root/$tree"/bin/targets/mediatek/filogic/*initramfs-kernel.bin \
         "$root/$tree"/bin/targets/mediatek/filogic/*initramfs-recovery.itb; do
    [ -f "$f" ] && { FIT="$f"; break; }
done
[ -n "$FIT" ] || { echo "没找到 initramfs 的 FIT 产物，world 未产镜像" >&2; exit 1; }
echo "   FIT: $FIT"

KD="$(ls -d "$root/$tree"/build_dir/target-*/linux-*/linux-*/ | head -1)"
KD="${KD%/}"
echo "   内核目录: $KD"

echo "== [2/4] 从 FIT 抽出 initrd 并重打包 =="
docker run --rm -v "$root":/repo -v "$work":/work -w /work "$img" bash -euo pipefail -c '
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
            print(f"   initrd: {ln} bytes @file+{vp} (compression 见 FIT)")
        q = (vp+ln+3) & ~3
    elif tok == 4:
        q += 4
    else:
        break
PY
' -- "/repo/${FIT#"$root"/}"

# rootfs 来自 initramfs-kernel.bin 的 initrd；解包 → 禁用 vendor 模块 → CRC32 单流重打包
docker run --rm -v "$work":/work -w /work "$img" bash -euo pipefail -c '
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
    xz -9 --check=crc32 -c ../smoke.cpio > ../initrd-smoke.cpio.xz
    xz -l ../initrd-smoke.cpio.xz
'

echo "== [3/4] QEMU 启动 + 核验 =="
# 关键断言：内核引导 → initramfs 解包 → /init → procd → 关键 UCI 落盘
cat > "$work/drive.sh" <<'DRV'
#!/usr/bin/env bash
set -uo pipefail
K="$1"; INITRD="$2"; OUT="$3"
# 每条都以 SENTINEL=值 的形式回显，断言只认哨兵 → 不会被无关行误匹配
cmds=(
  'echo "RELMARK=$(cat /etc/openwrt_release | head -1)"'
  'echo "CONGMARK=$(cat /proc/sys/net/ipv4/tcp_congestion_control)"'
  'echo "QDISC=$(cat /proc/sys/net/core/default_qdisc)"'
  'echo "RAMARK=$(grep -v "^#" /etc/sysctl.d/98-ipv6-wan.conf | grep -o "accept_ra = 2")"'
  'echo "LANRA=$(uci get dhcp.lan.ra)"'
  'echo "LANNDP=$(uci get dhcp.lan.ndp)"'
  'echo "LANDHCPV6=$(uci get dhcp.lan.dhcpv6)"'
  'echo "WAN6MASTER=$(uci get dhcp.wan6.master)"'
  'echo "WAN6RA=$(uci get dhcp.wan6.ra)"'
  'echo "UPNP=$(uci get upnpd.config.enabled)"'
  'echo "SVCS=$(ps w | grep -E "procd|ubusd|netifd|odhcpd" | grep -v grep | wc -l)"'
  'echo "FWMARK=$(nft list tables | grep -c "table inet fw4")"'
  'echo DONE_9f3a'
)
( sleep 45
  for c in "${cmds[@]}"; do sleep 2; printf '%s\n' "$c"; done
  sleep 25 ) | timeout 220 qemu-system-aarch64 -M virt -cpu cortex-a53 -smp 2 -m 512 \
    -kernel "$K" -initrd "$INITRD" \
    -display none -serial stdio -monitor none -nic none -no-reboot \
    -append 'console=ttyAMA0,115200 loglevel=7 rdinit=/init' > "$OUT" 2>&1
true
DRV
chmod +x "$work/drive.sh"
docker run --rm -v "$work":/work -v "$root/$tree":/repo:ro "$img" \
    bash /work/drive.sh "/repo/${KD#"$root/$tree"/}/arch/arm64/boot/Image" /work/initrd-smoke.cpio.xz /work/boot.log || true

# ---- 4. 断言（哨兵精确匹配，避免 ^1$ 这类弱匹配误判） ----
pass=0; fail=0
check() { # <描述> <grep -E 模式>
    if grep -qE "$2" "$work/boot.log"; then echo "   ✅ $1"; pass=$((pass+1))
    else echo "   ❌ $1"; fail=$((fail+1)); fi
}
echo "== [4/4] 结果 =="
check "内核引导（Linux version banner）"        'Linux version .*360t7m-slim@build'
check "initramfs 被解包"                        'Freeing initrd memory'
check "用户态 /init 拉起"                       'Run /init as init process'
check "preinit 运行"                            'init: - preinit -'
check "procd 完成 init 阶段"                    'procd: - init -'
check "BBRv3 拥塞控制生效"                      'CONGMARK=bbr'
check "fq pacing 队列生效"                      'QDISC=fq'
check "WAN accept_ra=2（IPv6 透传前置）"        'RAMARK=accept_ra = 2'
check "LAN ra=hybrid"                           'LANRA=hybrid'
check "LAN ndp=hybrid"                          'LANNDP=hybrid'
check "LAN dhcpv6=hybrid"                       'LANDHCPV6=hybrid'
check "wan6 为 relay master"                    'WAN6MASTER=1'
check "wan6 ra=hybrid"                          'WAN6RA=hybrid'
check "UPnP 默认开启（uci-defaults 生效）"      'UPNP=1'
check "四个常驻服务均在"                        'SVCS=4'
check "firewall4 nft 表已装"                    'FWMARK=1'
check "交互 shell 可达"                         'root@ImmortalWrt'

echo
if [ "$fail" -eq 0 ]; then
    echo "   QEMU 冒烟: $pass/$pass 全部通过"
else
    echo "   QEMU 冒烟: $pass 通过 / $fail 失败"
    cp "$work/boot.log" /tmp/qemu-smoke-fail.log
    echo "   完整日志留存: /tmp/qemu-smoke-fail.log"
    exit 1
fi
echo "  注：MT7981 无 QEMU 机型，MTK WiFi / HNAT / NAND 硬件路径不在本次覆盖范围。"
