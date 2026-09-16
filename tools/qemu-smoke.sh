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
# 构建/initrd 的公共逻辑与踩坑见 tools/qemu-lib.sh。
#
# 注意：本脚本会先 distclean 再用调试内核重建，产物哈希偏离出厂值；
#       跑完要拿回出厂哈希，再 `just build<树>` 一次即可。
set -euo pipefail

tree="${1:?用法: qemu-smoke.sh <tree>（例 mt798x-6.6）}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
img="${IMG:-mt798x-builder:24.04-v4}"
# shellcheck source=tools/qemu-lib.sh
. "$root/tools/qemu-lib.sh"

[ -d "$root/$tree" ] || { echo "没有 $tree 目录" >&2; exit 1; }

work="$(mktemp -d)"
QEMU_ENV_WRITTEN=0
# 注意用 if 而不是 `[ ... ] && cmd`：条件为假时后者返回 1，而 EXIT trap 里
# 最后一条命令的返回值会**改写整个脚本的退出码** —— 现象是明明成功却 rc=1。
cleanup() { if [ "$QEMU_ENV_WRITTEN" = 1 ]; then rm -rf "$root/$tree/env"; fi; rm -rf "$work"; }
trap cleanup EXIT

echo "== [1/4] 准备调试内核 + rootfs（首次构建，之后走缓存）=="
qemu_ensure_artifacts "$root" "$root/$tree" "$work"

echo "== [2/4] 禁用 vendor 模块自加载 + 重打包 initrd =="
qemu_repack_initrd "$work"

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
docker run --rm -v "$work":/work "$img" \
    bash /work/drive.sh /work/Image /work/initrd-run.cpio.xz /work/boot.log || true

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
