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
  HZ_100 保留；kmod-dummy（hnat-detect 用）/kmod-ifb（eqos 用）为真依赖；
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
7. 结论性盘点：libstdcpp6（~513KB 压缩）唯一持有者是 l1util→libl1parser（C++），
   而 l1util 只被 /etc/hotplug.d/net/09-fix-mtwifi-mac 调用来写 WiFi MAC——
   摘它要改写该 hotplug 并连带摘 l1parser 三件套，风险（写错 MAC = 设备身份错）
   大于收益，留待单独一轮；tc-tiny 只服务 eqos 槽位 32+ 的软件整形
   （1–31 走硬件 HQoS），保留；模块 .ko 未剥符号（全树仅省 19KB 压缩，
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
