# 360t7m-immortalwrt-slim

> 给 Qihoo 360T7M（MT7981B）的深度定制固件：把社区原版砍掉三分之一，
> 在供应商内核上跑通主线级 BBRv3 与全链路硬件卸载，编译参数逐包分层——
> 八轮优化，每一项都有构建日志和产物哈希背书。

双内核线并行维护：

| | 6.6 稳定线 | 6.12 新线 |
|---|---|---|
| 底座 | ImmortalWrt 24.10 | ImmortalWrt 25.12（APK 时代） |
| 内核 | 6.6.133 + mt_wifi 7.6.6.1 | 6.12.103 + mt_wifi 7.6.6.1 |
| 产物 |  186 包 / 14.15MB / sha256 `93422303…` |  164 包 / 15.74MB / sha256 `9db2ad54…` |

## 成绩单（相对社区原版 full 固件）

| 项 | 原 full 版 | 本项目 | 怎么做到的 |
|---|---|---|---|
| 固件体积 | 17.2MB | **14.16MB / 15.75MB** | 九轮裁剪 + zstd-19 squashfs |
| 软件包数 | 306 | **186 / 164** | USB/存储/代理/DDNS 全栈清退，每个幸存包反查过依赖 |
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

14 核全量约半小时，工具链与 dl 缓存跨次复用：

```sh
just build66 / build612             # 6.6 稳定线 / 6.12 新线 全量构建
just pick66 / pick612 sysupgrade    # 取刷机镜像到 out/（或 initramfs=救砖镜像 / all）
just smoke66                        # 冒烟：树内全新编译 dnsmasq
just builder                        # 重建自包含构建器镜像（FROM ubuntu:24.04）
```

构建在 rootless docker 容器内进行（镜像 v3，dpkg 集合与原镜像逐一比对一致），
任意机器克隆即建，无隐藏本地依赖。

## 文档

- [`mt798x-6.6/README-slim.txt`](mt798x-6.6/README-slim.txt) — 九轮优化全过程：裁剪清单、BBRv3 移植、
  KERNEL_ 通道清扫、分层参数、BBR 覆盖 bug 修复、fq pacing 补装
- [`mt798x-6.12/README-slim.txt`](mt798x-6.12/README-slim.txt) — 新线移植记录（PRECAL/netif_rx 补丁、
  mtkhnat 契约差异）、UPnP 栈补齐与同步的对齐策略
