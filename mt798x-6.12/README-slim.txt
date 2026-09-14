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

实测：sysupgrade.itb 16,507,144 → 15,753,480 字节（-736KiB，sha256 f879bfb5…），
包数 159 → 164（+5 净：加 UPnP 7 包、减 nettle/gmp/hogweed 3 包，另 libcap-ng
等转入）；**在新增整个 UPnP 栈的同时仍比上一轮小 736KiB**。
rootfs 全量 ELF NEEDED 闭包审计 0 悬空依赖。
