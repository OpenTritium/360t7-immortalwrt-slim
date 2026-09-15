360T7M 自编译 slim 精简版（ImmortalWrt 24.10 底座 + 内核 6.6.133 + MTK 闭源 mt_wifi 7.6.6.1）
构建时间：2026-09-14

本目录产物 = 之前 selfbuild-immortalwrt-mt798x-6.6（full 版）的裁剪优化版。

【与 full 版对比】
- 软件包：306 → 186 个（-120）
- sysupgrade.bin：17.2MB → 14.16MB
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

【第九轮：死配置清算 + 死重清退（2026-09-14）】
本轮目标从"继续砍体积"转为"先确保每一项都已生效"——第八轮那个 BBR 覆盖 bug
说明"配置写了不等于生效"，于是把 sysctl / 内核选项 / 包依赖逐条与运行期对齐。

1. fq pacing 补装（真 bug，与第八轮同类）：
   /etc/sysctl.d/99-perf-tuning.conf 一直设 net.core.default_qdisc=fq，但两树内核
   都是 # CONFIG_NET_SCH_FQ is not set（默认 fq_codel）——写 sysctl 不报错，静默
   回落。BBRv3 因此一直没有 pacing 队列。修复：target/linux/mediatek/filogic/
   config-6.6|6.12 显式 CONFIG_NET_SCH_FQ=y。核验：vmlinux 符号 fq_qdisc_ops
   已内建（两树各 1 处）。
2. 死 sysctl 清理：10-default.conf（base-files）里的 net.core.bpf_jit_enable=1 /
   bpf_jit_kallsyms=1 两树 BPF_JIT 均为 n，纯死配置，删。
3. conntrack 双写消除：package/kernel/linux/files/sysctl-nf-conntrack.conf 写
   100000，99-perf-tuning.conf 写 65536，按文件名序后者生效——100000 是障眼法，
   统一为 65536。
4. dnsmasq DNSSEC 编译项关闭（CONFIG_PACKAGE_dnsmasq_full_dnssec=n）：
   /etc/config/dhcp 全程无 dnssec/trust-anchor 选项（authoritative 1 属 auth 特性，
   与 dnssec 无关）。连带退出 libnettle + libhogweed + libgmp 三包（ELF NEEDED
   反查确认只服务 dnsmasq）。核验：新 dnsmasq 的 NEEDED 只剩
   libubox/libubus/libgcc/libc，无 libnettle。要 DNSSEC 时重建即可。
5. 6.6 无使用者死重清退（provides 感知反查逐个确认依赖为空）：
   libncurses + terminfo（385K+36K，仅服务已裁掉的 gdb/tmon/fdisk 类）、
   iw、switch、regs、mii_mgr、mhz、libatomic、libcap。
   其中 mhz 的真正引入通道是 package/emortal/autocore/Makefile 里
   `+(TARGET_mediatek||TARGET_mvebu):mhz`——cpuinfo 对 mediatek 分支写死
   cpu_freq=""，从不调用 mhz，属模板残留，已从 DEPENDS 摘除。
   注意保留 ethtool：其包依赖反查为空，但 /sbin/smp.sh 的 disable_gro_fraglist
   运行期调用它（未声明的隐式依赖），属"必须留"。
6. 6.6 OPENSSL_OPTIMIZE_SPEED 对齐（此前被显式关成 n，6.12 默认 y）：
   package/libs/openssl/Makefile 会把 TARGET_CFLAGS 的 -O% 换成 -O3。
   代价实测 +219KB（压缩后 libcrypto 1274K→1493K），换本机 TCP 的 TLS 握手
   （LuCI https / apk / wget）提速，属有意识取舍。
7. 6.12 内核死码对齐：BPF_SYSCALL=BPF_JIT=n（6.6 第四轮已关，6.12 漏了）。
8. 6.6 内核配置纳入版本管理：.gitignore 增加 !/.config——此前两树的 .config
   都不在 git 里，"确定性重建"其实依赖工作区残留。现两树 .config 均已入库。
9. 结论性盘点（本轮不改）：KALLSYMS_UNCOMPRESSED=y 来自 include/kernel-defaults.mk
   的硬编码，非本树可配；模块 .ko 未剥符号（实测剥掉全树只省 19KB 压缩，
   而 oops 里会失去模块符号，不值得，弃）；CPU_FREQ/THERMAL 虽= y 但 MT7981 DTS
   无 opp-hz/cpu-thermal 节点（只有 mt7987.dtsi 有），属死码但不值得动 DTS。

实测：sysupgrade.bin 14,746,396 → 14,162,716 字节（-570KiB），包数 197 → 186（-11）
（产物 sha256 见顶层 README.md 与 out/——镜像内嵌 REVISION=DISTRIB_REVISION，
其值取决于本文件所在提交，故不在本文件内自引用哈希）；rootfs 全量 ELF NEEDED 闭包审计 0 悬空依赖。
注：仍为静态核验（NEEDED/符号/包清单/产物哈希）——MT7981 无 QEMU 机型，
真机启动验证需刷机，与本项目既有验证口径一致。

【第十一轮：IPv6 透传 + UPnP 默认开启（2026-09-14）】
场景驱动：局域网设备自带 tailscale（依赖 UPnP/NAT-PMP/PCP 拿 IPv4 直连，
否则长期挂 DERP 中继）；且拿不到光猫超管密码 → 改不了桥接 → 没有 DHCPv6-PD，
ISP 只经光猫 RA 下发一个 /64。

1. odhcpd hybrid 透传（package/base-files/files/etc/uci-defaults/99-ipv6-passthrough）：
   先查清"是否拿到 PD"这件事挂在哪——读 odhcpd 源码 src/config.c 的
   odhcpd_reload()/ubus_has_prefix() 确认：判断走 ubus 的 ipv6-prefix 属性，
   而该属性挂在 dhcpv6 客户端接口（wan6）上，不在 wan 上。所以 master 段
   必须写成 dhcp.wan6.interface='wan6'，写成 wan 会让 master 永远判成
   "无 PD"，在 PD 场景下误入 relay。
   - dhcp.lan.ra='hybrid' / dhcp.lan.ndp='hybrid'
   - dhcp.wan6 = { interface wan6, ignore 1, master 1, ra hybrid, ndp hybrid }
   行为自动分档：有 PD → master 不入 relay，LAN 走 server（等同改动前）；
   无 PD（光猫路由模式） → LAN 降级 relay：中继上游 RA 到 LAN、清 PIO 的
   on-link 位（odhcpd 显式 `&~ND_OPT_PI_FLAG_ONLINK`，使 LAN 设备经本机做网关）、
   ndp relay 做邻居代理 + learn_routes 默认 1 装 /128 回程路由。
   核验 relay 路径不夹带 server 侧的 max_preferred/valid_lifetime 钳制
   （那是 send_router_advert 里的，relay 只改 flags 不碰 lifetime）——
   上游 RA 的 30 分钟 preferred 直接原样透传，不会把全局地址提前作废。
   安全回落：wan6 未上线 → master 缺失 → LAN 的 hybrid 解析回 server，即原行为。
2. WAN 接受上游 RA（etc/sysctl.d/98-ipv6-wan.conf）：
   net.ipv6.conf.wan.accept_ra=2。内核文档 ip-sysctl.rst 明确：forwarding=1 时
   accept_ra=1 被忽略，只有 2（Overrule forwarding behaviour）才生效——
   本项目 net.ipv6.conf.all.forwarding=1 恒开，所以只能是 2，否则路由器自己
   拿不到上游地址，relay 也就无源可继。
3. UPnP 默认开（etc/uci-defaults/99-upnp-enable）：上游包 enabled 缺省 0，
   每次刷机要手点；改默认 1。secure_mode/perm_rule 保持上游不动。

验证方式（本轮新增手段）：借助 qemu-user-static + binfmt_misc + user
namespace chroot，把真实 rootfs 跑起来执行 uci-defaults，核验生成后的 UCI
配置（见下）。无法验证的部分如实记录：qemu 缺 MT7981 机型、且 userns 下
chroot 内 /proc 不可用，odhcpd 本体起不来（fopen /proc/net/ipv6_route 失败），
故 relay 的**运行时**行为仍为源码级论证，非实机观测。

实测：sysupgrade.bin 14,162,716 → 14,172,956 字节（+10,240，三个新文件与
文本），包数 186 不变，sha256 见顶层 README.md。

【第十一轮补记：位级确定性构建（2026-09-14）】
上一轮 README 写了"确定性重建成立"，实测推翻——每次构建镜像哈希都变。
逐层定位后修掉两处（本树走 opkg，无 apk 那处问题），现已位级可复现
（同一 REVISION 连跑两次，字节与 sha256 完全相同）。

1. 内核 banner 嵌入 docker 容器 ID。
   CONFIG_KERNEL_BUILD_USER / CONFIG_KERNEL_BUILD_DOMAIN 为空时，内核回落到
   whoami@hostname，而构建在容器里跑 → banner 变成 `root@e358215914db`，
   容器 ID 每次不同。修复：本树 .config 钉死
   CONFIG_KERNEL_BUILD_USER="360t7m-slim" / CONFIG_KERNEL_BUILD_DOMAIN="build"。
   核验：两个不同容器构建产出同一个 Image 哈希。

2. SOURCE_DATE_EPOCH 依赖脚本 mtime。
   scripts/get_source_date_epoch.sh 在无 version.date、无 git 时回落到
   try_mtime（脚本自身 mtime = 克隆时间），跨机器不可复现。
   修复：本树放 version.date（OpenWrt 标准机制，优先于 git/mtime）。

3. 6.12 的 apk 打包另有"包内嵌构建墙钟时间"的问题（PKG_SOURCE_DATE_EPOCH
   回落到 try_mtime 后又被导出为 SOURCE_DATE_EPOCH，apk 见该变量非空即对
   所有文件统一盖章）。本树用 opkg，ipkg-build 已有
   --mtime/$PKG_SOURCE_DATE_EPOCH + --sort=name，故不适用；细节见
   mt798x-6.12/README-slim.txt 第十一轮补记。

实测：sysupgrade.bin 14,172,956 字节，sha256 43ded935…（两次构建一致）。

【第十一轮补正：按 OpenWrt 官方口径复核 IPv6 中继（2026-09-14）】
复核来源：odhcpd 上游 README 的选项表（权威）、OpenWrt 25.12+ 的
NDP Relay 实践文（littlenewton.uk，含 f0d8553 修复与完整 uci 配置）、
OpenWrt 论坛多个 relay 实例。结论：配置结构正确，但上一轮漏了一条链，
且有几处需要写清楚依据。

■ 官方/社区的标准 relay 配置（多来源一致）
    dhcp.wan6: master=1, ra=relay, ndp=relay
    dhcp.lan:  ra=relay, ndp=relay

■ 我的配置与它的差异，及依据
1. 用 hybrid 而非 relay。
   官方示例面向"确定没有 PD"的固定场景；hybrid 是 README 明确列出的合法取值
   （ra/dhcpv6 为 disabled|server|relay|hybrid，ndp 为 disabled|relay|hybrid）。
   odhcpd 的 odhcpd_reload() 里 hybrid 按"master 有没有 ipv6-prefix"二选一：
   有 PD → LAN 走 server（等同原行为），无 PD → LAN 走 relay。同一条固件
   两种组网都对，且运营商改了配置也不会失联。这是刻意优于官方示例的地方。
2. 补 dhcpv6 链（上一轮漏配，本轮加上）。
   ra / dhcpv6 / ndp 在 odhcpd 里是三个独立开关（config.c 各自解析、各自判
   hybrid）。只配 ra+ndp 时，src/router.c 会走这一段：
       /* Rewrite M/O flags unless we relay DHCPv6 */
       if (c->dhcpv6 != MODE_RELAY) {
           adv->nd_ra_flags_reserved &= ~(ND_RA_FLAG_MANAGED | ND_RA_FLAG_OTHER);
           adv->nd_ra_flags_reserved |= c->ra_flags & (MANAGED|OTHER);   // 默认 other-config
       }
   即把上游的 M/O 抹掉再按本地 ra_flags 重写。上游若是 stateful（RA 置 M、
   PIO 不带 A），LAN 设备既不能 SLAAC（无 A）也不会去要 DHCPv6（M 被抹）
   ——一个地址都拿不到。加上 dhcpv6=relay 后 M/O 原样透传，DHCPv6 也中继。
   中继实现核对 src/dhcpv6.c relay_client_request()：slave 收到客户端请求后
   封装 Relay-Forward，发往 **master 接口上的 ff05::1:3**（ALL_DHCPV6_SERVERS），
   不需要显式服务器地址；因此 master 侧也必须开 dhcpv6（我的配置两侧都开了）。
   （注意：README 里的 dhcpv6_relay_servers 选项在本版 odhcpd 中尚不存在。）
3. 显式写出 ra_slaac=1 与 ndproxy_routing=1。两者本就是 odhcpd 默认值
   （ra_slaac 默认 1、ndproxy_routing 默认 1），写出来是固化意图 + 防上游改默认。
4. ignore=1 保留。核对两树 odhcpd 源码：wan6 段的 UCI `ignore` 选项 odhcpd
   根本不读（6.6 版 config.c 里连这个字段都没有，6.12 版仅出现在 host 段的
   ip/iid="ignore" 值判断）。它只服务 dnsmasq 的 --no-dhcp-interface，无副作用。

■ 关于"前缀分配"的取舍（为什么是 relay 不是再切子网）
SLAAC 的最小分配单元就是 /64（IID 占满 64 位），无法从上游给的单个 /64 里
再切出子前缀给 LAN —— 这正是必须用 NDP/RA 中继的原因，也是官方文档把 relay
描述为"in case no delegated prefixes are available"的场景。本固件的处理：
  有 PD   → LAN 走 server，按委派前缀 + 网络配置里的 ip6assign 正常分配；
  无 PD   → LAN 走 relay，LAN 设备直接取用**与上游同一个 /64** 内的地址，
            经本机三层转发，无 NAT、无二次分配。

■ 主接口
dhcp.wan6.master='1' 必需：relay 只在 master 与 slave 之间转发，没有 master
时 hybrid 会整体回落 server。

■ 运行时验证（qemu-user + binfmt_misc + 嵌套 userns/netns，真实 rootfs）
做了对照实验，两个都是可观测的硬证据：
  A 显式 relay：odhcpd 日志 "Enabling services with lan0/wan0 running"，
    且内核 /proc/sys/net/ipv6/conf/lan0/proxy_ndp 由 0 变 **1**
    —— NDP 中继确实初始化了；全程无 "Invalid ... mode" 报错，选项名/值合法。
  B 我的 hybrid（用 -u 禁用 ubus）：proxy_ndp 保持 0，回落 server ——
    与源码一致。
  B 顺带暴露一个必须写明的依赖：hybrid→relay 需要 ubus（config.c 里
  `if (config.use_ubus && !ubus_has_prefix(...))`）。真机上 ubusd 常驻，
  满足条件；万一无 ubus，回落 server 是安全侧，不会配出半吊子中继。
  odhcpd 本体无法在容器里完整跑起 relay 转发（netifd 在测试环境起不来接口
  对象，relay 的端到端转发未实测），此项如实标注为源码级结论。

【第十一轮补正二：无上游时为何回落 server，以及 relay 触发条件（2026-09-14）】

■ 回落是上游的显式设计（src/config.c 的 hybrid 解析）
    i->ra     = (master && master->ra     == MODE_RELAY) ? MODE_RELAY : MODE_SERVER;
    i->dhcpv6 = (master && master->dhcpv6 == MODE_RELAY) ? MODE_RELAY : MODE_SERVER;
    i->ndp    = (master && master->ndp    == MODE_RELAY) ? MODE_RELAY : MODE_DISABLED;
  注意 ndp 回落的是 DISABLED —— 上游也认为"无上游时代理无意义"；
  而 ra/dhcpv6 回落 SERVER，即完全等同于原版 OpenWrt 的 LAN 行为。

■ 而且这个回落并非无意义：odhcpd 会优雅降级
  实测（qemu + netns + 真实 rootfs，给 lan0 一个 ULA）odhcpd 日志：
      rfc9096: lan0: add fd12:3456:789a:1::1/64
      No default route present, setting ra_lifetime to 0!
  对应 src/router.c:878（server 模式专有，relay 不走这段）：
      if (default_route && valid_prefix)
          adv.h.nd_ra_router_lifetime = htons(ra_lifetime ...);
      else
          adv.h.nd_ra_router_lifetime = 0;   /* 明确宣告"我不是默认路由" */
  即：LAN 设备仍能 SLAAC 出 ULA（本机管理、mDNS、LAN 内服务可用），
  但路由器把 RA 的 router lifetime 置 0，设备不会把它当默认网关，
  因而不会把全局流量黑洞。这是刻意的安全降级。
  同一测试中抓到的 RA 为 M=0 O=1，与上述一致。

■ 为什么用 SERVER 而非 DISABLED 作为回落
  1. 等同原版行为，最少意外；
  2. 模式在每次 reload 时重新解析，wan6 一上线（无 PD → master=RELAY）
     LAN 即自动切到 relay，开机顺序或 WAN 瞬断都不需要人工干预；
  3. 若回落 DISABLED，WAN 短暂中断会连带把 LAN 的本地 IPv6 也拆掉。

■ relay 的触发条件（本场景关键，已核实）
  odhcp6c 把 RA 派生的 /64 与 DHCPv6-PD 前缀分别导出为两个变量
  （src/script.c: PREFIXES ← PD；RA_ADDRESSES ← RA 的 A 位 /64）。
  OpenWrt 的 lib/netifd/dhcpv6.script 映射为：
      PREFIXES     -> proto_add_ipv6_prefix  -> netifd 的 ipv6-prefix
      RA_ADDRESSES -> proto_add_ipv6_address -> netifd 的 ipv6-address
      RA 的 /64 只有当 mask=64 且 PREFIXES 为空且 EXTENDPREFIX=1 时才
      额外上报为 ipv6-prefix（RFC 7278 的 extendprefix 选项，默认不开）。
  odhcpd 的 ubus_has_prefix() 查的正是 ipv6-prefix，于是：
      光猫路由模式（只有 RA /64、无 PD）-> wan6 有 ipv6-address、无 ipv6-prefix
                                        -> master=RELAY -> LAN=relay   ✓
      运营商下发 PD                    -> ipv6-prefix 存在
                                        -> master 非 relay -> LAN=server ✓
  两种组网都自动落到正确的分支。

  ⚠️ 坑：若给 wan6 设了 option extendprefix '1'，RA 的 /64 会被上报为
  ipv6-prefix，odhcpd 便误判为"有 PD"，relay 永不激活。本固件不设该项，
  将来也不要设。

【第十二轮：无 modem 相关的精简复核（2026-09-15）】

结论：4G/5G 相关的**包**早已不在固件里，本轮只挖出一处内核死重。

■ 包层面（本来就没有，无需精简）
  两树 manifest 里 modem 相关命中为零（唯一的 jsonfilter 是 "fi-lte-r" 误匹配）。
  .config 中 kmod-mhi-*/kmod-wwan/kmod-rmnet/kmod-qrtr-mhi/kmod-usb-net-cdc-mbim/
  kmod-usb-net-cdc-ncm/kmod-usb-net-qmi-wwan*/kmod-pcie_mhi*/libmbim 等
  全部 is not set —— 未编译、未安装。
  package/mtk/applications/5g-modem（12MB 源码）仍在树内，但无任何包被选中，
  是早先几轮清理后的源码残留，不进固件，删除收益为零，保留以备将来。

■ 内核层面（本轮实际收益）
  查到 PCIe 整栈仍在编译，而 MT7981 的 pcie@11280000 控制器在 SoC dtsi 里
  是 status="disabled"，360T7 板级 DTS 对其无任何覆盖 → 永不 probe。
  该总线的唯一用途是外置无线卡或 4G/5G 模块（M.2），本机都没有。
  另确认 USB 侧已无可删：CONFIG_USB_SUPPORT 只剩开关与 arch 常量，
  USB HCD 符号早在前几轮即为 0。

  注意 CONFIG_PCI 本身**不能**关：MTK vendor WiFi 的
  drivers/net/wireless/wifi_utility/Makefile 里 `obj-y += pci_mediatek_rbus.o`
  是无条件编译（MT7986 外置卡的 RBUS 路径），编译期引用 pci_scan_root_bus /
  pci_bus_add_devices / pci_add_resource 等核心 PCI API，关掉即编译失败
  （已实测报错）。故采取"关上层、留核"的折中。
  无线卸载不受影响：WED 用的是 mtk_wed.o/mcu/wo 内部路径，不含
  mtk_wed_pcie.o（MT7986 外置卡专用），WED 代码也无 CONFIG_PCI 条件。

  改动（target/linux/mediatek/filogic/config-6.6|6.12）：
    CONFIG_PCI / PCI_DOMAINS / PCI_DOMAINS_GENERIC / PCI_MSI  保留
    PCIE_MEDIATEK_GEN3 / PCIEPORTBUS / PCIEAER / PCIEASPM / PCIE_PME / PCI_DEBUG  关闭
  实测：vmlinux 中 PCI* 符号 158.3KB -> 132.9KB（6.6）、161.5KB -> 135.5KB（6.12）；
  WED 符号完好（53/56 个）；sysupgrade 体积 -20KiB 两树一致。

【第十三轮：干净克隆可复现性订正（2026-09-15）】
新引入的 GitHub CI（build.yml）本质是「干净克隆到干净机器上构建」，
用它做端到端验证时暴露出两个此前的说法不成立：

1. 构建依赖未入库的 archive/
   justfile 原先从 archive/*.git 取 REVISION，而 archive/ 在 .gitignore 里。
   新克隆构建直接 exit 128。已改为：
     - 树内 revision 文件（入库）作为 REVISION 来源
     - feeds.conf.default 用 ^sha 固定，feeds/ 不入库、首次构建自动拉取
   README 原先「任意机器克隆即建，无隐藏本地依赖」的说法就此成立。

2. 提交 .config 反而破坏构建（我们自己引入的回归）
   把 .config 纳入版本管理后，新克隆必然失败。根因是 scripts/feeds 的
   refresh_config()（line 878，由「feeds update」结尾调用）：
   发现 .config 存在就执行 make defconfig，而此刻 package/feeds/* 符号链接
   尚未建立，feed 里的包被当作不存在，.config 被抹掉数千行
   （CONFIG_PACKAGE_luci 等消失），后续 package/install 报
   cannot find dependency luci / lua-cjson / wget-ssl。
   上游该函数的守卫是「没有 .config 就直接返回」，即假设 .config 由用户后续
   生成 —— 我们提交它恰好踩中。已改回忽略 .config，内容存
   defconfig/360t7-slim.config，由 justfile 在 feeds 就绪后注入，且不跑 defconfig。

3. 已发布哈希实际来自旧工具链（重要订正）
   端到端跑通后比对发现：干净克隆的产物哈希与工作区记录不一致。
   逐层定位到 staging_dir —— 工作区的工具链编译于 09-14 03:05，
   早于 version.date（当晚 22:37 引入，用于固定 SOURCE_DATE_EPOCH）。
   工具链是「只建一次、之后复用」的，所以此前的「位级可复现」只在
   同一份 staging_dir 内成立；换机器/干净克隆会得到不同产物。
   本轮起，README 记录的哈希改为**干净克隆**构建的结果，
   并新增 just distclean66/distclean612（连 staging_dir 一起删）
   以便在工作区复现干净克隆的哈希。

实测（本次全部在干净克隆中完成，无 archive/、无 .config、无 feeds、无 staging_dir）：
  6.6  14,142,236 字节  sha256 41915e1c…
  6.12 15,720,712 字节  sha256 dd7152d9…
两树构建均 exit 0。
