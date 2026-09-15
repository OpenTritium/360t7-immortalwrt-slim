360T7M 自编译 slim 精简版（ImmortalWrt 25.12 底座 + 内核 6.12.103 + mainline flowtable mtkhnat + mt_wifi 7.6.6.1）
基线提交：df1de4b（6.12 移植全记录见该提交说明）

【编译参数（2026-09-14 第七轮，与 6.6 树同策略）】
- 分层：内核 -O2（CC_OPTIMIZE_FOR_PERFORMANCE）；用户态全局回落
  -Os -pipe -mcpu=cortex-a53（EXTRA_OPTIMIZATION 撤掉全局 -O2，
  保留 -fno-caller-saves -fno-plt -fomit-frame-pointer）
- 热路径包内钉 -O2 -fomit-frame-pointer：dnsmasq-full（DNS/DHCP 持续转发）、
  dropbear（SSH）、uhttpd（WebUI）
- LTO：dnsmasq/dropbear 显式启用 -flto=auto（上游 PKG_BUILD_FLAGS:=lto 本受
  全局 USE_LTO 门控，未开即死配置，此处按 include/package.mk 开关语义显式化）；
  uhttpd 上游未选 LTO 不加；全局 USE_LTO（EXPERIMENTAL）不开
- 符号去除：USE_SSTRIP=y 全二进制 sstrip；KALLSYMS 暂留（真机稳定后关）
- 已关加固：pkg/kernel SSP、FORTIFY_SOURCE（沿用"不用安全换性能"基线）
- 不做：全局 gc-sections、内核 LD_DEAD_CODE_DATA_ELIMINATION（QEMU 无法验证
  启动）、-O3
- 6.12 线特性备忘：mtkhnat 走 mainline flowtable HW offload（无 6.6 的
  HNAT/kmod-ipt-nat 编译契约）、APK 包管理、mtwifi-cfg-ucode（无 lua）
- 实测镜像：sysupgrade.itb 16.7MB → 16.55MB（16,552,202 字节，sha256 5be9266a…），
  159 包不变；V=s 核验 dnsmasq CFLAGS 带 -O2 -flto=auto（fuse-linker-plugin），
  冷层 -Os 无 -O2；本树构建已切换自包含 v3 镜像验证通过

【第八轮：BBR 覆盖修复 + 内核加固税对齐（2026-09-14）】
- turboacc init 缺省 tcpcca cubic → bbr，uci-defaults 模板同步——
  修复开机把 BBRv3 默认值覆盖回 cubic 的 bug（此前 BBR 等于从未生效）。
- 内核加固项对齐 6.6 方针（不用安全换性能）：FORTIFY_SOURCE、
  HARDENED_USERCOPY、SCHED_STACK_END_CHECK、SLAB_FREELIST_HARDENED/RANDOM、
  ARM64_SW_TTBR0_PAN 全部关闭（generic/config-6.12）。
- 审计结论：CPU_IDLE/cpufreq 全关 = 无 DVFS 全程最高频率（即最强性能档）；
  HZ_100 保留；kmod-dummy（hnat-detect 用）为真依赖；kmod-ifb（eqos 用）
  第十四轮随 eqos 一并移除；
  HNAT 走 vendor hook_toggle 路径开机自启，与 nft flowtable 无关。
- 实测：sysupgrade.itb 16.5MB（16,507,146 字节，sha256 9524362f…，159 包；卸掉加固税后较第七轮再瘦约 44KB）。

【第九轮：内核 bump 尝试与跟随策略（2026-09-14）】
- 尝试 6.12.103 → .109/.108：失败，根因是补丁集分叉。429 三件套
  （v6.18 spinand dirmap 重构）已被 .105+ stable 原生吸收（tarball 抽验
  spinand_create_rdesc 等已在），其余 pending/backport 补丁与
  ImmortalWrt master 有约 80 处结构性分歧，逐个适配等于接手整个补丁集维护。
- 决策：内核小版本跟随 zheshifandian 上游（当前 .103，8/16 批量 bump
  .97→.103）；他 bump 我们重放他的适配提交，不做 kernel.org 抢跑。
- CachyOS 补丁盘点：唯一适用项 BBRv3 已在用；BORE 调度器评估后放弃
  （路由器转发走 softirq，不经过 CFS/EEVDF，纯增分叉）；zstd 库换血
  （18.6k 行）、cachy 大礼包、fixes 均为 x86/桌面向，全部不适用。
- 顺带修复：导入时漏 add 的 .gitignore 已补上（树内新文件此前不会
  出现在 git status）。

【第十轮：UPnP 栈补齐 + 与 6.6 的对齐清扫（2026-09-14）】
本轮首要项是功能缺口：6.12 线此前没有 UPnP（miniupnpd / luci-app-upnp 均
未选），与 6.6 线不一致。其余为与 6.6 第九轮同批的对齐/死配置清算。

1. UPnP 补齐（新增 7 包）：miniupnpd-nftables（nftables 变体，非 iptables）、
   luci-app-upnp、luci-i18n-upnp-zh-cn，连带 libcap-ng / libuuid1 /
   libpthread / librt。核验 rootfs：/usr/sbin/miniupnpd（NEEDED =
   libnftnl/libmnl/libcap-ng/libuuid/libc）、/etc/init.d/miniupnpd、
   /etc/config/upnpd、/usr/share/nftables.d/{table-post,chain-post/forward,
   chain-post/srcnat,chain-post/dstnat}/20-miniupnpd.nft、
   www/luci-static/resources/view/upnp/upnp.js + menu/acl json 齐备。
   enabled 缺省 0（与 6.6 一致，LuCI 里开启）。
2. fq pacing 补装（与 6.6 第九轮同一 bug）：99-perf-tuning.conf 设
   net.core.default_qdisc=fq，但内核 # CONFIG_NET_SCH_FQ is not set，
   BBRv3 pacing 一直缺队列。修复：filogic/config-6.12 显式 CONFIG_NET_SCH_FQ=y。
3. 内核死码对齐 6.6 第四轮：CONFIG_BPF_SYSCALL / CONFIG_BPF_JIT 关。
   核验：新内核 .config 中二者均 not set，vmlinux 含 fq_qdisc_ops。
4. dnsmasq DNSSEC 编译项关闭 → libnettle / libhogweed / libgmp 三包退出
   （与 6.6 同处理；/etc/config/dhcp 无 dnssec 选项）。
5. 死 sysctl 清理：10-default.conf 的 bpf_jit_enable / bpf_jit_kallsyms
   （BPF_JIT=n，纯死配置）。
6. 6.6 内核配置入库口径同步：.gitignore 增加 !/.config，两树 .config 纳入 git。
7. 结论性盘点：libstdcpp6（~513KB 压缩）唯一持有者是 l1util→libl1parser（C++）。
   第十四轮用 readelf 复核后**订正**：libiwinfo.so.20230701 本身就有硬
   DT_NEEDED → libl1parser.so（iwinfo 的 C 源 iwinfo_mtk_l1util.c 调用
   l1_get_chip_id_by_ifname/get_devname），且 l1parser 是 netifd 的 WiFi 上报
   路径（mtwifi.uc 与 netifd/wireless/mtwifi.sh 都 l1parser.open()）——
   不是「改一个 hotplug 就能摘」而是 fork vendored WiFi 链路，已决定放弃。
   tc-tiny 只服务 eqos 槽位 32+ 的软件整形（1–31 走硬件 HQoS），第十四轮随
   eqos 整体移除；模块 .ko 未剥符号（全树仅省 19KB 压缩，
   代价是 oops 丢模块符号，弃）。

实测：sysupgrade.itb 16,507,144 → 15,753,480 字节（-736KiB）
包数 159 → 164（+5 净：加 UPnP 7 包、减 nettle/gmp/hogweed 3 包，另 libcap-ng
等转入）；**在新增整个 UPnP 栈的同时仍比上一轮小 736KiB**。
rootfs 全量 ELF NEEDED 闭包审计 0 悬空依赖。
（产物 sha256 见顶层 README.md 与 out/——镜像内嵌 REVISION 取决于本文件所在提交，
故不在本文件内自引用哈希）

【第十一轮：IPv6 透传 + UPnP 默认开启（2026-09-14）】
与 6.6 树同批同实现（详细论证见 mt798x-6.6/README-slim.txt 第十一轮）。
场景：局域网设备自带 tailscale（要 UPnP/NAT-PMP/PCP 拿 IPv4 直连）；
拿不到光猫超管密码 → 改不了桥接 → 无 DHCPv6-PD，只有光猫 RA 的一个 /64。

1. odhcpd hybrid 透传（etc/uci-defaults/99-ipv6-passthrough）：
   dhcp.lan.ra/ndp=hybrid + dhcp.wan6={interface wan6, ignore 1, master 1,
   ra hybrid, ndp hybrid}。段名必须用 wan6 而非 wan——odhcpd 判断"有无 PD"
   读的是 ubus 的 ipv6-prefix，挂在 dhcpv6 客户端接口上。有 PD 则 LAN 走
   server（等同改动前），无 PD 则 LAN 降级 relay（中继 RA + 清 on-link 位 +
   NDP 代理 + /128 回程路由）。wan6 未上线时回落 server，不会失联。
   本树 odhcpd 版本 2026.06.29（6.6 树为 2025.10.02），两版 hybrid 逻辑一致
   （均含 ubus_has_prefix 门控），已逐行比对确认。
2. WAN accept_ra=2（etc/sysctl.d/98-ipv6-wan.conf）：forwarding=1 时内核忽略
   accept_ra=1，只有 2 生效（ip-sysctl.rst）。
3. UPnP 默认开（etc/uci-defaults/99-upnp-enable）：配合上一轮新装的
   miniupnpd-nftables 栈，省掉每次刷机手点。

实测：sysupgrade.itb 15,753,480 字节（尺寸不变——三处新增均为文本，
落在 squashfs 已满 256K 块内），包数 164 不变，sha256 见顶层 README.md。

【第十一轮补记：位级确定性构建（2026-09-14）】
上一轮 README 写了"确定性重建成立"，实测推翻——每次构建镜像哈希都变。
逐层定位后修掉三处，两树现已位级可复现（连跑两次 sha256 完全相同）。

1. 内核 banner 嵌入 docker 容器 ID。
   CONFIG_KERNEL_BUILD_USER / CONFIG_KERNEL_BUILD_DOMAIN 为空时，
   内核回落到 whoami@hostname，而构建在容器里跑 → banner 变成
   `root@e358215914db`，容器 ID 每次不同。修复：两树 .config 钉死
   CONFIG_KERNEL_BUILD_USER="360t7m-slim" / CONFIG_KERNEL_BUILD_DOMAIN="build"。
   核验：两个不同容器的构建产出同一个 Image 哈希。

2. SOURCE_DATE_EPOCH 依赖脚本 mtime。
   scripts/get_source_date_epoch.sh 在无 version.date、无 git 时回落到
   try_mtime（脚本自身 mtime = 克隆时间），跨机器不可复现。
   修复：两树各放 name.version.date（OpenWrt 标准机制，优先于 git/mtime）。

3. apk 包内嵌构建墙钟时间（仅 6.12）。
   这是最隐蔽的一处：PKG_SOURCE_DATE_EPOCH 对 luci 等"无源码日期"的包会
   回落到 get_source_date_epoch.sh 的 try_mtime（= 构建时刻），而
   include/package-pack.mk 把它导出为 SOURCE_DATE_EPOCH。apk 的
   apk_get_build_time()（apk-tools src/common.c）一旦发现该环境变量非空，
   就对【所有】文件统一返回它，于是 .apk 内每个文件的 mtime = 构建时刻。
   首次尝试用 find -exec touch -hcd 钉 staging 目录 mtime —— 完全无效，
   因为 apk 根本不读文件 mtime。
   修复（一行）：include/package-pack.mk 的导出改为
     export SOURCE_DATE_EPOCH=$$(if $(SOURCE_DATE_EPOCH),$(SOURCE_DATE_EPOCH),$$(PKG_SOURCE_DATE_EPOCH))
   即优先用全局固定的 SDE。核验：luci-base 连续三次 clean 重建 apk 位相同；
   全树 124 个 apk 跨两次构建全部相同。

6.6 树走 opkg，ipkg-build 已有 --mtime/$SOURCE_DATE_EPOCH + --sort=name，
故只有第 1、2 两处适用。

实测（同一 REVISION 连跑两次，字节与哈希均相同）：
  6.6  sysupgrade.bin 14,172,956 字节  sha256 43ded935…
  6.12 sysupgrade.itb 15,757,576 字节  sha256 40eea99e…

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

【第十四轮：包与 feed 精简（2026-09-15）】
取证方法：解析已构建产物的包数据库（apk `lib/apk/db/installed`，
带 `o:` origin 字段可定位每个包的 feed 来源）做 reverse-dependency 闭包，
`readelf -d` 核 ELF NEEDED，再把真 rootfs 放进 qemu-user chroot 实跑。

■ 1. feed 层：删 routing / telephony / video
  证据：apk 数据库的 origin 统计 = base 138 / packages 3 / luci 23，
  routing·telephony·video 各 0 个包。本树 telephony 甚至从未 clone 成功
  （feeds/ 下只剩 telephony.tmp/），构建照样通过，证明其贡献为 0。
  改动：feeds.conf.default 只留 packages 与 luci。
  packages feed 只贡献 3 个包（miniupnpd 等），luci feed 23 个；
  不需要 `feeds install -a` 全量灌，但保留 install -a 以免 feed 升级时
  漏装新的传递依赖（体积不进固件，只影响 feeds/ 目录）。

■ 2. eqos 限速整体移除
  本树的 luci-app-eqos-mtk 是 nft 重写版（DEPENDS = +tc +nftables
  +kmod-sched-core +kmod-ifb +kmod-mediatek_hnat），功能可用；移除是为与 6.6
  对齐（6.6 那个是坏的，见该树说明）并省体积：
  tc-tiny（压缩 142KB）+ kmod-sched-core + kmod-ifb + sch_htb/sch_hfsc/
  sch_tbf/sch_ingress + act_*/cls_* 全套流量整形模块（实测修复后 rootfs 内
  sch_*.ko / act_*.ko / ifb.ko 归零）。
  如将来要恢复 per-IP/MAC 限速：勾回 luci-app-eqos-mtk 即可，其依赖会自动带回。

■ 3. 主题：本树未装 luci-theme-argon，维持 bootstrap（与 6.6 统一后两树一致）

■ 4. 结论：不做的项（含此前判断的订正）
  libstdcpp6（压缩 513KB）——**放弃**。第十轮曾记「l1util 只被
  /etc/hotplug.d/net/09-fix-mtwifi-mac 调用来写 MAC，摘它要改写该 hotplug」，
  本轮用 readelf 订正：libiwinfo.so.20230701 自身硬 DT_NEEDED → libl1parser.so
  （iwinfo 的 C 源 iwinfo_mtk_l1util.c 调用 l1_get_chip_id_by_ifname/
  by_devname），且 l1parser 是 netifd 的 WiFi 上报路径（lib/wifi/mtwifi.uc 与
  lib/netifd/wireless/mtwifi.sh 都 `l1parser.open()`）。
  摘它等于 fork vendored iwinfo C 模块 + 用 ucode 重写 L1 profile 解析，
  风险（WiFi 起不来）远大于 513KB，放弃。
  wpad-openssl（730KB）/ openssl core（1.97MB）为深依赖，不划算。

■ 验证（真 rootfs 实跑）
  qemu-user chroot 执行产物内 /www/cgi-bin/luci（ucode）：
    未改动 rootfs → LuCI 正常分发并返回自己的 500 页（chroot 无 ubusd/rpcd）；
    仅 stub 3 个必须依赖常驻 daemon 的调用后 → 403 + **完整渲染登录表单**
    （luci_username/luci_password/Log in/cascade.css 齐备，
    <title>OpenWrt | Overview</title>）。
  说明界面链路在移除 eqos / tc 后完好。

实测（干净克隆流程，distclean 后构建）：
  6.12 15,458,568 字节  sha256 84cd39bf…  159 包
  （对照：上轮干净克隆 15,720,712 字节 / 164 包 → -256KiB / -5 包）
两树构建均 exit 0。

■ 构建期踩坑
  parallel 跑两树 world（-j7 ×2，14 核）会让 6.6 的 toolchain/gdb 在
  libiberty/regex.c 上失败（configure 探针 ac_cv_type_pid_t 被判 no，
  进而 `#define pid_t int` 与系统 typedef 冲突）。属宿主竞争，
  串行重建即通过。本机请勿同时跑两树。
