#!/usr/bin/env bash
# QEMU WebUI 冒烟：把真实固件在 qemu-system-aarch64 的 `virt` 机型上启动，
# 用 user 网络把 guest 的 80 端口转发到宿主，供人直接在浏览器里点 LuCI。
#
# 与 tools/qemu-smoke.sh 的区别：那个只跑串口断言、不需要网卡；这个要多一张
# virtio 网卡（所以内核必须带 CONFIG_VIRTIO_NET，走 env/kernel-config），
# 并在 guest 里把网卡配好、划进 lan 防火墙区，否则 fw4 会把入向包丢掉。
#
# 用法：tools/qemu-webui.sh <tree> [端口]      例：tools/qemu-webui.sh mt798x-6.12 8080
# 环境：SKIP_BUILD=1 跳过构建（复用已有带调试符号的产物）；KEEP=秒 保持时长
# 注意：会先 distclean 重建内核，产物哈希偏离出厂值；跑完 `just build<树>` 复原。
set -euo pipefail

tree="${1:?用法: qemu-webui.sh <tree> [端口]（例 mt798x-6.12）}"
port="${2:-8080}"
keep="${KEEP:-14400}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
img="${IMG:-mt798x-builder:24.04-v4}"
# shellcheck source=tools/qemu-lib.sh
. "$root/tools/qemu-lib.sh"

[ -d "$root/$tree" ] || { echo "没有 $tree 目录" >&2; exit 1; }

# 工作目录固定放在树内（已 gitignore）：QEMU 容器是 detach 的，脚本退出后
# 它还要继续读这里的 Image/initrd，所以不能用 mktemp。
work="$root/$tree/.qemu-cache/run-webui"
log="$work/boot.log"
name="qemu-webui-$(basename "$tree")"
# 重跑前先清掉同名旧容器，否则 -p 端口会冲突
docker rm -f "$name" >/dev/null 2>&1 || true
mkdir -p "$work"
: > "$log"
QEMU_ENV_WRITTEN=0
# 注意用 if 而不是 `[ ... ] && cmd`：条件为假时后者返回 1，而 EXIT trap 里
# 最后一条命令的返回值会**改写整个脚本的退出码** —— 现象是明明成功却 rc=1。
cleanup() { if [ "$QEMU_ENV_WRITTEN" = 1 ]; then rm -rf "$root/$tree/env"; fi; }
trap cleanup EXIT

echo "== [1/3] 准备调试内核 + rootfs（首次构建，之后走缓存）=="
qemu_ensure_artifacts "$root" "$root/$tree" "$work"

echo "== [2/3] 禁用 vendor 模块自加载 + 重打包 initrd =="
qemu_repack_initrd "$work"

echo "== [3/3] QEMU 启动（宿主 $port → guest 10.0.2.15:80）=="
# guest 侧配置：给 virtio 网卡配 slirp 约定的 10.0.2.15/24 + 默认路由，
# 再把 eth0 划进 lan 区（默认 input ACCEPT），否则 fw4 丢包导致页面打不开。
cat > "$work/drive.sh" <<'DRV'
#!/usr/bin/env bash
set -uo pipefail
K="$1"; INITRD="$2"; KEEP="$3"
cmds=(
  'echo "ETH=$(ls /sys/class/net | tr "\n" " ")"'
  # 给 virtio 网卡建一个正规的 netifd 接口（slirp 约定的 10.0.2.15/24，网关 10.0.2.2），
  # 再把它挂进 lan 区。注意 fw4 的 zone.network 认的是 **netifd 接口名**而不是内核
  # 设备名 —— 直接写 eth0 是不生效的，接口会留在区外被 REJECT
  # （现象：宿主 curl 连上就 "Connection reset by peer"）。
  'uci set network.qemu=interface; uci set network.qemu.device=eth0; uci set network.qemu.proto=static; uci set network.qemu.ipaddr=10.0.2.15; uci set network.qemu.netmask=255.255.255.0; uci set network.qemu.gateway=10.0.2.2; uci commit network'
  'i=0; while uci -q get firewall.@zone[$i].name >/dev/null 2>&1; do if [ "$(uci -q get firewall.@zone[$i].name)" = lan ]; then uci add_list firewall.@zone[$i].network=qemu; break; fi; i=$((i+1)); done; uci commit firewall'
  '/etc/init.d/network reload >/dev/null 2>&1; /etc/init.d/firewall reload >/dev/null 2>&1; echo "FW=reloaded"'
  'echo "ZONENET=$(uci -q get firewall.@zone[0].network | tr "\n" " ")"'
  '/etc/init.d/uhttpd running || /etc/init.d/uhttpd start; echo "UHTTPD=$(/etc/init.d/uhttpd running && echo running || echo stopped)"'
  'echo "LISTEN=$(netstat -ltn 2>/dev/null | grep -c ":80 ")"'
  'echo "LOCALHTTP=$(wget -q -O /dev/null http://127.0.0.1/ && echo ok || echo fail)"'
  'echo "IPADDR=$(ip -4 -o addr show eth0 | awk "{print \$4}")"'
  'echo WEBUI_READY'
)
( sleep 45
  for c in "${cmds[@]}"; do sleep 2; printf '%s\n' "$c"; done
  sleep "$KEEP" ) | qemu-system-aarch64 -M virt -cpu cortex-a53 -smp 2 -m 512 \
    -kernel "$K" -initrd "$INITRD" \
    -display none -serial stdio -monitor none -no-reboot \
    -netdev user,id=n0,hostfwd=tcp:0.0.0.0:"$4"-10.0.2.15:80 \
    -device virtio-net-device,netdev=n0 \
    -append 'console=ttyAMA0,115200 loglevel=7 rdinit=/init' 2>&1
DRV
chmod +x "$work/drive.sh"

# QEMU 用 -d detach：它必须在本脚本退出后继续活着（用户要慢慢点页面），
# 也不能受我这边进程生死影响（用 `&` + wait 时被杀过一次，exit 137）。
# `-p` 不能省：QEMU 跑在容器里，它的 hostfwd 只绑容器的 netns，
# 不 publish 的话宿主根本连不上（现象：本机 curl 立刻 connection refused）。
docker run -d --name "$name" -p "$port:$port" -v "$work":/work "$img" \
    bash /work/drive.sh /work/Image /work/initrd-run.cpio.xz "$keep" "$port" >/dev/null

# 等 guest 自报就绪。注意 `-d` 之后容器的 stdout 归 docker logs 管，
# 不能再指望 `docker run ... > 文件`（那样只会拿到容器 ID）。
for _ in $(seq 1 120); do
    docker logs "$name" 2>&1 | grep -q WEBUI_READY && break
    docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true || {
        echo "QEMU 容器已退出，日志尾部：" >&2; docker logs "$name" 2>&1 | tail -20 >&2; exit 1; }
    sleep 2
done
docker logs "$name" > "$log" 2>&1
grep -q WEBUI_READY "$log" || { echo "guest 未就绪，日志尾部：" >&2; tail -20 "$log" >&2; exit 1; }

grep -E "^(ETH|FW|ZONENET|UHTTPD|LISTEN|LOCALHTTP|IPADDR)=" "$log" || true

# 宿主侧真连一次，确认转发通了（这才是「冒烟过没过」的证据）
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:$port/" || echo 000)"
echo
echo "宿主探测 http://127.0.0.1:$port/ → HTTP $code"
if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
    echo "WEBUI_OK"
else
    echo "WEBUI_FAIL（页面没起来，QEMU 仍在跑，日志：$log）"
fi
for ip in $(hostname -I 2>/dev/null); do
    echo "   → 也可以试 http://$ip:$port/"
done
echo "   QEMU 容器：$name（停止：docker rm -f $name）；${keep}s 后自停"
