# 360t7m-immortalwrt-slim

> 给 Qihoo 360T7M（MT7981B）的深度定制固件：把社区原版砍掉三分之一，
> 在供应商内核上跑通主线级 BBRv3 与全链路硬件卸载，编译参数逐包分层——
> 十四轮优化，每一项都有构建日志和产物哈希背书。

双内核线并行维护：

| | 6.6 稳定线 | 6.12 新线 |
|---|---|---|
| 底座 | ImmortalWrt 24.10 | ImmortalWrt 25.12（APK 时代） |
| 内核 | 6.6.133 + mt_wifi 7.6.6.1 | 6.12.103 + mt_wifi 7.6.6.1 |
| 产物 |  161 包 / 12.93MB / sha256 `b3cffb37…` |  159 包 / 15.46MB / sha256 `84cd39bf…` |

## 成绩单（相对社区原版 full 固件）

| 项 | 原 full 版 | 本项目 | 怎么做到的 |
|---|---|---|---|
| 固件体积 | 17.2MB | **12.93MB / 15.46MB** | 十四轮裁剪 + zstd-19 squashfs |
| 软件包数 | 306 | **161 / 159** | USB/存储/代理/DDNS/打印/限速全栈清退，每个幸存包反查过依赖 |
| 拥塞控制 | BBRv1 | **BBRv3 + fq pacing** | CachyOS 官方回移植（6.6/6.12 两版），内建默认 |
| NAT 转发 | 软转发 | **硬件卸载** | vendor HNAT（有线）+ WHNAT/WARP（无线）+ fullcone |
| 编译参数 | 全树一刀切 | **逐包分层** | 热路径 -O2+LTO，冷路径 -Os，`-mcpu=cortex-a53`，全二进制 sstrip |
| 内核杂税 | 服务器级默认 | **归零** | cgroups/MPTCP/io_uring/swap/BPF/加固项全部关闭，mitigations=off |

顺带修了两个"设了等于没设"的社区级 bug：turboacc 每次开机把拥塞控制覆盖回 cubic；
BBRv3 设了却因内核缺 `sch_fq` 而没有 pacing 队列。

IPv6 与内网穿透按实际组网场景做了预置（见下节）。

## IPv6 透传与内网穿透（针对光猫路由模式预置）

两种上游形态下都开箱即用，无需进 LuCI 手配：

| 上游形态 | 行为 |
|---|---|
| 光猫桥接 / 运营商下发 DHCPv6-PD | LAN 走 odhcpd `server`，按委派前缀下发（等同社区默认） |
| **光猫路由模式、拿不到超管密码、无 PD** | LAN 自动降级 `relay`：中继上游 RA、清 PIO 的 on-link 位、NDP 代理 + 路由学习 |

第二行是这套预置的主要目的：拿不到光猫超管密码就改不了桥接，ISP 只经光猫 RA 下发一个 /64。
`odhcpd` 的 hybrid 模式按"上游到底有没有 PD"自动二选一，因此**同一条固件在两种组网下都对**，
不依赖手工切换，也不会在运营商改配置后失联。

落地点（两树一致）：

- `etc/uci-defaults/99-ipv6-passthrough` — `dhcp.lan` 与 `dhcp.wan6` 的 **ra / dhcpv6 / ndp 三条链**均设 hybrid，
  `wan6` 设 relay master；`ra_slaac=1`（保留上游 PIO 的 A 位让 LAN 设备 SLAAC）与 `ndproxy_routing=1` 显式固化
- `etc/sysctl.d/98-ipv6-wan.conf` — `net.ipv6.conf.wan.accept_ra=2`（转发开启时内核会忽略 `=1`，
  必须用 2，否则路由器自己都拿不到上游地址）
- `etc/uci-defaults/99-upnp-enable` — UPnP IGD / NAT-PMP / PCP 默认开启

产物可复现：两树都做了位级确定性构建（连跑两次 sha256 完全相同），
详见各自 `README-slim.txt` 的第十一轮。

三条链缺一不可：`ra` 中继 RA、`ndp` 代理邻居、`dhcpv6` 保住中继 RA 的 M/O 位——
只配前两条时，上游若为 stateful（RA 置 M、PIO 不带 A），odhcpd 会抹掉 M/O，
LAN 设备既不能 SLAAC 也不会要 DHCPv6，一个地址都拿不到。

**UPnP 默认开启**是为内网设备自建的 tailscale：走 UPnP/NAT-PMP/PCP 拿到 IPv4 直连，
而不是长期挂在 DERP 中继上。上游包默认 `enabled=0`（每次刷机都要手点），此处改为默认开；
`secure_mode=1` 与"默认拒绝 + 仅放行 1024-65535"的 perm_rule 保持上游原样——映射只对发起请求的那台主机生效。

## 设备

MT7981B 双核 A53 @1.3GHz · 内存改装 512M · 128M NAND + 108M 大分区社区 U-Boot · 全千兆无 USB。

> ⚠️ 改装机红线：官方 `preloader.bin` / `bl31-uboot.fip`（256M DDR3 时序）刷了就变砖，永远不要碰。

## 刷机

| 方式 | 6.6 | 6.12 |
|---|---|---|
| 系统内 sysupgrade | `sysupgrade.bin` | `sysupgrade.itb` |
| U-Boot web 直刷（192.168.1.1） | ❌（tar 不认） | ✅ |
| 保底：web 喂 initramfs 进内存系统再刷 | `initramfs-kernel.bin` | `initramfs-recovery.itb` |

产物均在 `<树>/bin/targets/mediatek/filogic/`；跨线刷机不保留配置。

## 构建

全量约半小时（14 核），工具链与 dl 缓存跨次复用。
并行度默认**留 4 核给宿主**（14 核 → `-j10`），避免构建期间机器没法干别的；
想用满核：`JOBS=$(nproc) just build66`。

```sh
just build66 / build612             # 6.6 稳定线 / 6.12 新线 全量构建
just pick66 / pick612 sysupgrade    # 取刷机镜像到 out/（或 initramfs=救砖镜像 / all）
just smoke66                        # 冒烟：树内全新编译 dnsmasq
just vm-smoke66 / vm-smoke612       # QEMU 冒烟：qemu virt 上真启动固件（见下）
just builder                        # 重建自包含构建器镜像（FROM ubuntu:24.04）
```

### QEMU 冒烟（`just vm-smoke*`）

MT7981 没有 QEMU 机型，所以此前一切验证都是静态的（ELF NEEDED 闭包、包清单、
产物哈希）。静态核验查不出「配置写了没生效」——第九轮那个 `default_qdisc=fq`
缺 `sch_fq`、以及 turboacc 开机把 BBR 覆盖回 cubic 的 bug，就是这么漏过去的。

`tools/qemu-smoke.sh` 把**真实固件**（本树 world 产物的内核 + 完整 rootfs；
内核额外带 `env/kernel-config` 里的 PL011/virtio 调试符号，其余与出厂一致）在
`qemu-system-aarch64 -M virt` 上真启动，覆盖「内核引导 → initramfs 解包 →
`/init` → preinit → procd → UCI 落盘 → 服务常驻」这一段，并断言关键配置真生效：

- 内核引导 + initramfs 解包 + `Run /init as init process`
- `procd: - early -/- ubus -/- init -` 三阶段
- `tcp_congestion_control=bbr`、`default_qdisc=fq`（BBRv3 + pacing 真在跑）
- `net.ipv6.conf.wan.accept_ra = 2`
- `dhcp.lan.ra=hybrid` / `dhcp.wan6.master=1`（IPv6 中继确实落到 UCI）
- `upnpd.config.enabled=1`（uci-defaults 生效）
- procd / ubusd / netifd / odhcpd 四个常驻进程 + `table inet fw4`

两树实测均 **17/17 断言全通过**（6.6 与 6.12 同一套哨兵断言）。

实现上有几处必须照做（脚本内已注释，改动前先读）：

1. initramfs 不是内建的，而是 FIT 里的 `initrd-1` 节点、**xz 压缩**，需按偏移抽出。
   两树产物名不同：6.6 出 `initramfs-kernel.bin`，6.12 出 `initramfs-recovery.itb`。
2. 重打包必须 `xz --check=crc32` 且单流——本树内核只编了 CRC32，默认 CRC64 与
   `-T0` 多块流会被内核解码器**静默**拒绝（现象：`Freeing initrd memory` 之后
   直接 panic "Unable to mount root fs"，看不到 `Run /init`）。
3. 必须禁用 `conninfra`/`mt_wifi`/`mtk_warp`/`mtkhnat` 的模块自加载——无 MT7981
   寄存器时 conninfra 会 NULL 解引用 panic。
4. 调试符号走 `<tree>/env/kernel-config`（`LINUX_KCONFIG_LIST` 末尾 → 合并优先级
   最高）。6.12 比 6.6 多出 `CONFIG_NSM`/`CONFIG_VIRTIO_DEBUG` 两个 `depends on
   VIRTIO` 的符号，env 打开 VIRTIO 后它们才首次可见，非交互的 `syncconfig`
   碰到 `(NEW)` 会去读 stdin 然后失败——脚本已把两者写死为默认值 `n`。
5. `docker run` 要带 `-i` 且 stdin 给 `/dev/null`（同上 syncconfig 读 stdin 的坑）。
6. 必须先 `distclean`：env 会改内核哈希，`build_dir` 里上轮的 kmod 仍带旧哈希，
   `package/install` 会报 `cannot find dependency kernel (= <hash>)`。

> ⚠️ 该冒烟需要写 `<tree>/env/kernel-config` 以打开 PL011 串口 / virtio，因而会
> **重建内核**，使 `build_dir` 的产物哈希偏离出厂值。脚本已自带 `distclean`，
> 跑完要拿回出厂哈希请再 `just build<树>` 一次即可。
> `env/` 已在 `.gitignore` 内，不会入库。
>
> 不需要开 `DEVTMPFS`：initramfs 里 `/dev` 确实是空目录，但内核给 `rdinit` 的
> fd 0/1/2 直接接在 console 驱动上，用户态写 stdout 不经过 `/dev/console`。
> 本冒烟就是在 `CONFIG_DEVTMPFS is not set` 的内核上全项通过的。
>
> 覆盖不到：mt_wifi 驱动、HNAT/WARP 硬件卸载、NAND/UBI 布局、真实 PHY/交换机。
> 这些仍只能靠真机刷写验证。

详见 `mt798x-6.6/README-slim.txt` / `mt798x-6.12/README-slim.txt` 的第十五轮记录。

构建在 rootless docker 容器内进行（镜像 v3，dpkg 集合与原镜像逐一比对一致），
新克隆即可构建，不依赖本机残留：

- `REVISION` 来自树内 `revision` 文件（入库），不再依赖未入库的 `archive/`
- feeds 在 `feeds.conf.default` 里用 `^sha` 固定；`feeds/` 不入库，首次构建自动按固定 sha 拉取
  （只保留 `packages` 与 `luci` 两条——`routing`/`telephony`/`video` 对本目标 0 贡献，见第十四轮）
- 因此同一提交在任意机器上重建，产物 sha256 一致

> ⚠️ 上面的哈希来自**干净克隆**（无 `staging_dir`）。若在工作区增量构建，
> 工具链是早先编译的（可能早于 `version.date` 引入 SOURCE_DATE_EPOCH 的时刻），
> 产物会与干净克隆不同。要核对本 README 的哈希，用 `just distclean66` 先删掉
> `staging_dir` 再构建。

## 自动化

四条 workflow，均可用 `workflow_dispatch` 手动触发：

| workflow | 触发 | 作用 |
|---|---|---|
| `build` | push/PR | 干净 runner 上全量构建两树，产出 artifact + SHA256SUMS。**这是下面几条的门禁** |
| `upstream-sync` | 每日 | 探测上游（padavanonly / zheshifandian），把我们的改动 rebase 到新上游，开 PR；冲突则开 issue |
| `feeds-update` | 每周一 | 把 feeds 的 `^sha` 推进到分支 HEAD，构建验证后开 PR |
| `release` | tag `v*` / 手动 | 两树全量构建 → **重建比对哈希**（不可复现则拒绝发布） → GitHub Release |
| `uboot` | 手动 / `uboot-revision` 变更 | 构建社区 U-Boot + ATF（`hanwckf/bl-mt798x`，`SOC=mt7981 BOARD=360t7`），产物存 artifact |

`auto-merge` 监听 `build` 成功，将带 `automerge` 标签的 PR（feeds-update / Dependabot）squash 合并。
`upstream-sync` 的 PR **不打该标签**：上游 bump 内核或驱动时编译通过但行为可能变化，需人工核对
`mt798x-*/README-slim.txt` 里的内核跟随策略与 vendor 契约。

> 关于版本：workflow 里的 action 锁在当时的当前大版本
> （checkout v7 / cache v6 / upload-artifact v7 / download-artifact v8），
> 由 `dependabot.yml` 每周跟。runner 用 `ubuntu-24.04`（26.04 在 runner-images 里
> 仍是 public preview）；构建器基础镜像固定在 `ubuntu:24.04` 且**故意不自动升级**——
> 它承担复现原始构建环境的职责，换基础镜像会改变 glibc/gcc 从而破坏可复现性。

## 代码来源与致谢

本项目是**适配层**，不是从零实现的固件。上游与第三方来源如下：

| 组成 | 来源 | 说明 |
|---|---|---|
| 底座（6.6） | [`padavanonly/immortalwrt-mt798x-6.6`](https://github.com/padavanonly/immortalwrt-mt798x-6.6) | ImmortalWrt 24.10，vendor 内核补丁 |
| 底座（6.12） | [`zheshifandian/immortalwrt-mt798x-6.12`](https://github.com/zheshifandian/immortalwrt-mt798x-6.12) | ImmortalWrt 25.12，mainline flowtable mtkhnat |
| MTK WiFi 驱动栈 | [`hanwckf/immortalwrt-mt798x`](https://github.com/hanwckf/immortalwrt-mt798x) | mt_wifi / mtwifi-cfg / datconf / conninfra / l1util 的源码直取此处；`192.168.6.1` 默认 LAN 也是这条线的习惯 |
| **U-Boot + ATF** | [`hanwckf/bl-mt798x`](https://github.com/hanwckf/bl-mt798x) | 设备实际运行的引导器；见下节 |
| BBRv3 | CachyOS（Peter Jung） | 官方回移植补丁，源码内保留 `From:` 签名 |
| 其余 feed 包 | ImmortalWrt / OpenWrt 官方 feed | 按 `^sha` 固定，见 `feeds.conf.default` |

我们相对上游所做的改动，可随时导出核对（这也是 `upstream-sync` 的机制）：

```sh
git clone <上游> /tmp/up && cd /tmp/up && git checkout $(cat <树>/base-upstream)
# 树目录内容叠加到该基线之上，即为我们的全部改动
```

## U-Boot

设备的引导器是**社区 U-Boot（`hanwckf/bl-mt798x`）**，不是本仓库构建的那个。两者的区别必须分清：

| | 本仓库 `package/boot/uboot-mediatek` | `hanwckf/bl-mt798x` |
|---|---|---|
| 基线 | OpenWrt 主线 U-Boot（6.6 用 2024.10，6.12 用 2025.10） | MediaTek SDK U-Boot + ATF |
| 产出去向 | 随固件打包，作**设备自带引导器的备份**（`u-boot-mt7981_qihoo_360t7` 是设备符号强制保留项） | **设备实际运行的那个** |
| 512MB 内存 | 不支持（DDR 时序按 256MB 调） | **支持** —— 时序可训 512MB 颗粒，故改装机刷它 |

因此**不要刷本仓库构建出的 `bl31-uboot.fip` / `preloader.bin`** —— README 顶部那条红线警告说的就是它们。

若需要（重）刷社区 U-Boot：

```sh
just uboot          # 取 hanwckf/bl-mt798x（按 uboot-revision 固定 commit）并构建
just uboot-fetch    # 只取/更新源码
just uboot-status   # 查看固定 commit 与本地状态
```

产物落在 `out/`：`mt7981_360t7-fip-fixed-parts.bin`（FIP，含 BL2/BL31/U-Boot）与 `mt7981_360t7-bl2.bin`。
构建使用 `SOC=mt7981 BOARD=360t7`（官方 `build.sh` 支持的 board 名），全程容器内进行。

> ⚠️ 刷写引导器风险远高于刷固件，写错即变砖。相关教程见 hanwckf 的
> [mt798x uboot 使用说明](https://cmi.hanwckf.top/p/mt798x-uboot-usage)。本仓库只负责构建，不代办刷写。

## 文档

- [`mt798x-6.6/README-slim.txt`](mt798x-6.6/README-slim.txt) — 十五轮优化全过程：裁剪清单、BBRv3 移植、
  KERNEL_ 通道清扫、分层参数、BBR 覆盖 bug 修复、fq pacing 补装、QEMU 冒烟
- [`mt798x-6.12/README-slim.txt`](mt798x-6.12/README-slim.txt) — 新线移植记录（PRECAL/netif_rx 补丁、
  mtkhnat 契约差异）、UPnP 栈补齐与同步的对齐策略、QEMU 冒烟实测
