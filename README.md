# 360t7m-immortalwrt-slim

> 给 Qihoo 360T7M（MT7981B）的深度定制固件：把社区原版砍掉三分之一，
> 在供应商内核上跑通主线级 BBRv3 与全链路硬件卸载，编译参数逐包分层——
> 八轮优化，每一项都有构建日志和产物哈希背书。

双内核线并行维护：

| | 6.6 稳定线 | 6.12 新线 |
|---|---|---|
| 底座 | ImmortalWrt 24.10 | ImmortalWrt 25.12（APK 时代） |
| 内核 | 6.6.133 + mt_wifi 7.6.6.1 | 6.12.103 + mt_wifi 7.6.6.1 |
| 产物 |  186 包 / 14.16MB / sha256 `ae758806…` |  164 包 / 15.75MB / sha256 `3d0d0920…` |

## 成绩单（相对社区原版 full 固件）

| 项 | 原 full 版 | 本项目 | 怎么做到的 |
|---|---|---|---|
| 固件体积 | 17.2MB | **14.16MB / 15.75MB** | 九轮裁剪 + zstd-19 squashfs |
| 软件包数 | 306 | **186 / 164** | USB/存储/代理/DDNS 全栈清退，每个幸存包反查过依赖 |
| 拥塞控制 | BBRv1 | **BBRv3 + fq pacing** | CachyOS 官方回移植（6.6/6.12 两版），内建默认 |
| NAT 转发 | 软转发 | **硬件卸载** | vendor HNAT（有线）+ WHNAT/WARP（无线）+ fullcone |
| 编译参数 | 全树一刀切 | **逐包分层** | 热路径 -O2+LTO，冷路径 -Os，`-mcpu=cortex-a53`，全二进制 sstrip |
| 内核杂税 | 服务器级默认 | **归零** | cgroups/MPTCP/io_uring/swap/BPF/加固项全部关闭，mitigations=off |

顺带修了两个社区级 bug：turboacc 每次开机把拥塞控制覆盖回 cubic；
以及 BBRv3 设了却因内核缺 `sch_fq` 而失去 pacing 队列——两个都让"设了等于没设"。

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
