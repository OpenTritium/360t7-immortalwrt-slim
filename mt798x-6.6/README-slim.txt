360T7M 自编译 slim 精简版（ImmortalWrt 24.10 底座 + 内核 6.6.133 + MTK 闭源 mt_wifi 7.6.6.1）
构建时间：2026-09-14

本目录产物 = 之前 selfbuild-immortalwrt-mt798x-6.6（full 版）的裁剪优化版。

【与 full 版对比】
- 软件包：306 → 197 个（-109）
- sysupgrade.bin：17.2MB → 14.8MB
- 纯净性：0 个代理/ddns 类组件（passwall/ssr/clash/v2ray/xray/homeproxy/ddns 全无）

【裁剪内容】
1. USB/存储全栈（约 40 包）：360T7 硬件无 USB 口（DTS 无 usb 节点），
   usb-core/2/3/xhci/storage/uas、ext4/vfat/exfat/ntfs3/btrfs/autofs4、
   nls 系列、automount/block-mount/blkid/e2fsprogs/fdisk 等，全为死重。
2. turboacc 大礼包残留：luci-app-turboacc-mtk 的 DEPENDS 被我从 15 个包收敛为
   +kmod-mediatek_hnat +kmod-tcp-bbr +kmod-inet-diag +kmod-netlink-diag（它只实际使用 HNAT）。
   由此消失：ttyd、libwebsockets/libuv、btrfs、bonding、veth、ipvs、
   ipt-fullconenat/physdev/nat6、nft-socket/tproxy、nf-socket/tproxy 等。
3. bootloader 杂物：mt7986/mt7988/mt7981-ram 共 5 个 ATF blob（本机用不到）。
   注意：u-boot-mt7981_qihoo_360t7 + trusted-firmware-a-mt7981-spim-nand-ddr3
   是设备符号强制保留的（设备自带引导器备份），属正常。
4. 其他：shellsync（多拨同步工具，已从 ppp 的 select 中摘除）、kmod-mppe、
   kmod-macvlan、kmod-dummy、kmod-tun、kmod-zram/zram-swap、kmod-phy-aquantia
   （360T7 无 2.5G 独立 PHY）、kmod-crypto-user、libopenssl-legacy、
   luci-theme-bootstrap（保留 argon 主主题）、dnsmasq 的 dnstap/tftp 编译项。
   wireguard（应用户要求移除，含 udptunnel 依赖）、upnp、eqos 限速、HNAT/turboacc、MTK 全栈、web 升级
   （luci-app-package-manager）均保留。

【编译参数（第七轮起分层）】
- 优化级别：内核 -O2；用户态全局 -Os -pipe -mcpu=cortex-a53 -fno-plt；
  热路径（dnsmasq-full/dropbear/uhttpd）在包 Makefile 内单独 -O2，
  dnsmasq/dropbear 另开 LTO（详见第七轮记录）
- 已关闭：栈保护（pkg+kernel SSP）、内核 FORTIFY_SOURCE
- 保留：KALLSYMS（内核崩溃时可看符号，排障期不关）、USE_SSTRIP（全二进制符号抹除）
- 提示：make defconfig 会把 TARGET_OPTIMIZATION 重置为默认 -Os——现在与终态一致，
  无需担心；EXTRA_OPTIMIZATION 与热包 Makefile 内的追加不受 defconfig 影响。

【vendor 内核编译契约（重要，勿再裁）】
padavanonly 魔改内核的 mtk_eth_soc.c 在基础内核构建期就需要 HNAT 的通知符
（已写入 target/linux/mediatek/filogic/config-6.6 的 CONFIG_NET_MEDIATEK_HNAT=m），
而 HNAT 的 Kconfig 依赖 IP_NF_NAT —— 因此 kmod-ipt-nat / kmod-ipt-core /
kmod-nf-nat 这三个包是编译契约的一部分，删掉内核无法编译。运行期无人调用
iptables（防火墙是 nft/firewall4），属于"死但必要"的最小保留。

【刷机】
- 本变体与 full 版同为 qihoo_360t7 108M 大分区布局，sysupgrade.bin 为 tar 格式。
- 持久化配置从 21.02 系（①②）升级上来时无线配置不兼容，LAN/拨号等通用配置可用。
- 校验：sha256sums

【第二轮精简（2026-09-14 晚）】
- EIP197 硬件加密引擎全家（safexcel + eip197-mini-firmware + 约 15 个 crypto kmod）：
  仅服务 VPN/IPsec 场景，本固件已无 VPN，纯 NAT/WiFi 不经过内核 crypto API。
- wireguard/btrfs/aquantia/mppe 时代的孤儿依赖（blake2b/kpp/xxhash/zstd/hwmon/
  crc-ccitt/des/arc4/crypto-user 等）。
- dnsmasq 的 conntrack/nftset 编译功能（DNS 策略分流用，纯路由不需要），
  连带裁掉 libnetfilter-conntrack + kmod-nf-conntrack-netlink。
- 保留的真依赖：libuuid1（miniupnpd 用）、libopenssl-legacy（wpad-openssl 用）、
  kmod-lib-crc-ccitt（ppp 栈用）、kmod-lib-textsearch（nathelper ALG 用）。
- 内核加固清扫：ARM64_SW_TTBR0_PAN、SLAB_FREELIST_RANDOM/HARDENED、
  HARDENED_USERCOPY、SCHED_STACK_END_CHECK 全部关闭（叠加此前的
  STACKPROTECTOR/FORTIFY_SOURCE）。
- 编译参数：包与内核 -O2，另加 -fomit-frame-pointer。
- 参考社区思路：HNAT 硬件加速 + BBR + mtk-smp IRQ 亲和性 + mtkhqos 硬件限速
  已全数保留（MTK PPE 会向 conntrack 回写流量，限速/统计在硬件加速下仍有效）。

【第三轮优化（2026-09-14 深夜）】
- rootfs squashfs 压缩 xz → zstd level 19（解压快，适合按需读；代价：镜像
  14.83MB → 16.26MB。xz -9e 压缩率仍更高，zstd 换的是解压 CPU）
- TCP 拥塞控制升级 BBRv1 → BBRv3（CachyOS 6.6 官方回移植补丁
  kernel-patches/6.6/0001-bbr3.patch，含 rate_sample/ECN-LOW/TLP 基础设施；
  tcp_bbr.ko 130KB）。注意：BBR 只作用于路由器自身发起的 TCP（升级/opkg/测速），
  转发流量不经过本机 TCP 栈。
- 连接参数：nf_conntrack_max=65536、established 3600s、time_wait 30s、
  tcp_fastopen=3、slow_start_after_idle=0（/etc/sysctl.d/99-perf-tuning.conf）
- 首启自动向 U-Boot bootargs 追加 mitigations=off（99-tune-bootargs，带防护）
- 内核加固全清：+ARM64_SW_TTBR0_PAN、SLAB_FREELIST_*、HARDENED_USERCOPY、
  SCHED_STACK_END_CHECK

【第四轮：内核内建裁剪（2026-09-14）】
- 关闭 ATA（无 SATA，libata select SCSI 导致整个 SCSI 子系统内建）
- 关闭 ISDN、BPF_JIT/BPF_SYSCALL、BLK_DEV_LOOP、MEDIATEK_2P5GE_PHY（360T7 全千兆）
- 43 个 kmod 逐一反查全部有正当依赖（asn1←SIP ALG、crc32c←nft、textsearch←ALG）
- 镜像 16.26MB → 15.91MB；BLK_DEV_THROTTLING 因 kconfig.pl 合并怪癖仍为 y，
  无 cgroup IO 策略时零开销，接受

【第五轮：拥塞控制独苗化 + 内建再清（2026-09-14）】
- CUBIC 拥塞控制退场，BBRv3 转为内建（=y）并设为内核默认
  （CONFIG_DEFAULT_BBR=y，不再依赖 turboacc 运行时设置）
- EXT4 内建移除（USB 存储时代遗产，~400KB 常驻）
- 接受的内核核心链：ZSTD_COMPRESS→CRYPTO_ACOMP2、ECDH/ECC→CRYPTO_KPP、
  IP_MROUTE（被核心选中，无法单独摘除）
- 镜像 15.91MB → 15.72MB

【第六轮：CONFIG_KERNEL_ 通道清扫（2026-09-14）】
发现根配置的 CONFIG_KERNEL_* 行会被原样搬进内核配置并覆盖目标文件——
XR30 模板在此藏了一个"服务器级"内核。已清除：cgroups 全家桶（含 RDMA/
BPF/CPUACCT/PIDS/SCHED/MEMCG）、MPTCP、io_uring、组播路由（IPv4/v6
MROUTE+PIMSM）、SEG6 隧道、swap、fanotify、fhandle、AIO、ELF core、
POSIX mqueue、L3 master dev、BLK_DEV_THROTTLING（真凶即此通道）。
保留：DEBUG_FS（HNAT hook_toggle）、SYSRQ、SECCOMP、NAMESPACES（ujail）。
镜像 15.72MB → 15.46MB。
- 补刀：CONFIG_KERNEL_SWAP=y 走同一通道覆盖了 generic 的 not-set，已除。
  终态 15.44MB，内核配置中 CGROUPS/MPTCP/IO_URING/SWAP/IP_MROUTE/
  BLK_DEV_THROTTLING 全部归零。

【第七轮：分层编译参数 + LTO 精准启用（2026-09-14）】
- 全局回落：EXTRA_OPTIMIZATION 撤掉 -O2（此前 GCC 取最后一个 -O，全部用户态包
  等效 -O2，冷路径白白膨胀），终态 "-fno-caller-saves -fno-plt -fomit-frame-pointer"，
  冷路径（CLI/uci/ucode/openssl 等）回到 -Os -pipe -mcpu=cortex-a53。
- 热路径钉 -O2 -fomit-frame-pointer（包 Makefile 内 TARGET_CFLAGS +=）：
  dnsmasq-full（唯一持续跑流量的用户态进程：DNS/DHCP/MDNS）、
  dropbear（SSH 握手/加解密）、uhttpd（WebUI）。
- LTO 精准启用：dnsmasq/dropbear 上游本声明 PKG_BUILD_FLAGS:=lto，但受全局
  CONFIG_USE_LTO 门控（不开即死配置）；现按 include/package.mk 的开关语义显式补
  -flto=auto -fno-fat-lto-objects + 链接 -flto=auto -fuse-linker-plugin。
  uhttpd 上游未选 LTO，尊重上游只提 -O2。
- 全局 USE_LTO 评估后不开：上游标注 EXPERIMENTAL、全树 197 包受控面太大，
  收益以体积为主而非性能，与"刷机候选稳字优先"矛盾。gc-sections 维持 dropbear
  上游已选项，不做全局推广。
- 符号去除强度盘点：USE_SSTRIP=y（sstrip 抹除全部符号表/段头，已是极限）；
  内核 KALLSYMS 暂留（真机稳定后关）；KERNEL_DEBUG_INFO_REDUCED 只影响构建
  产物不进镜像。
- 覆盖面确认：OpenWrt 的 cmake.mk 已剥掉 CMake Release 默认 -O3，make/autotools/
  cmake 三类构建系统统一跟随 TARGET_CFLAGS，分层无死角；-mcpu=cortex-a53 由
  filogic/target.mk 全局生效。
- 不做清单：内核 LD_DEAD_CODE_DATA_ELIMINATION（纯省尺寸，QEMU 验证不了启动，
  刷机候选不冒险）、-O3（第二轮已论证弃用）。
- 实测：sysupgrade.bin 15.44MB → 14.75MB（14,746,398 字节，sha256 9f71cafa…），
  197 包不变；V=s 构建日志逐行核验：dnsmasq 实际 CFLAGS = -Os…-O2 -fomit-frame-pointer
  -flto=auto（链接 fuse-linker-plugin），uci（cmake 冷层）= -Os 无 -O2。

【第八轮：BBR 开机覆盖修复（2026-09-14）】
- 发现并修复：luci-app-turboacc-mtk 的 init 每次开机执行
  sysctl -w tcp_congestion_control，config_get 缺省值写死 cubic——
  第七轮之前的 BBRv3 内核默认值开机即被覆盖，等于从未生效。
- 修复：init 缺省值 cubic → bbr（LuCI 页面仍可手动切换）。
- HNAT 确认无恙：vendor 私有路径（debugfs hook_toggle），turboacc init
  开机自动置 1，不依赖 nft flowtable，防火墙配置无需加 flow_offloading。
- WiFi 硬件卸载链确认：WHNAT_SUPPORT=m + WARP_V2=y（ax3000 种子配置就位）。
- 包清单复核：kmod-dummy（hnat-detect 探测用）、kmod-ifb（eqos 限速用）
  均为真依赖。实测：sysupgrade.bin 14.75MB（14,746,398 字节，sha256 f9fbb481…，197 包，尺寸与第七轮持平——本轮只改开机默认值不改代码体积）。
