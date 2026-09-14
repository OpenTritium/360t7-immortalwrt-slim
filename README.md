# 360t7m-immortalwrt-slim

360T7M（固件目标 `qihoo_360t7`）专用裁调固件工厂：双内核线并行、可复现容器构建、八轮优化的最终态。

## 硬件基线（改配置前先看）

| 项 | 事实 | 推论 |
|---|---|---|
| SoC | MT7981B，双核 A53 @1.3GHz | 无 DVFS（cpufreq/CPU_IDLE 未编）= 全程最高频，即最强性能档 |
| 内存 | **改装 512M**（原装 256M DDR3） | **官方 `preloader.bin` / `bl31-uboot.fip` 永远不要刷**，时序按 256M 配，刷即变砖 |
| 闪存 | 128M NAND，108M 大分区社区 U-Boot | 两树镜像均按此布局生成；社区 U-Boot 本体不动 |
| 外设 | 无 USB 口，全千兆 | USB/存储栈已整体裁掉；2.5G PHY 已裁 |

## 双线现状（第八轮产物）

| | `mt798x-6.6` 稳定基线 | `mt798x-6.12` 新线 |
|---|---|---|
| 底座 / 内核 | ImmortalWrt 24.10 / 6.6.133 | ImmortalWrt 25.12 / 6.12.103 |
| 无线 | mt_wifi 7.6.6.1 + HNAT + WARP | 同左（mtkhnat，无 iptables 编译契约） |
| 产物 / 格式 | sysupgrade.bin（**tar**，197 包，14.75MB） | sysupgrade.itb（**FIT**，159 包，16.5MB） |
| sha256 | `f9fbb481…` | `9524362f…` |
| 包管理 | opkg | APK |

## 固件内已做（两树共有）

- **网络加速**：BBRv3（CachyOS 回移植，内建默认，turboacc 覆盖 cubic 的 bug 已修）、vendor HNAT 开机自启（debugfs `hook_toggle`，不依赖 nft flowtable）、WiFi WHNAT+WARP 硬件路径、fullcone、IRQ 亲和（mtk-smp）
- **编译参数分层**：热路径（dnsmasq/dropbear/uhttpd）`-O2 -fomit-frame-pointer`，dnsmasq+dropbear 加 `-flto=auto`；其余用户态 `-Os -pipe -mcpu=cortex-a53 -fno-plt`；内核 -O2；全二进制 sstrip
- **无加固税**（既定方针：不用安全换性能）：SSP/FORTIFY/SLAB_FREELIST/HARDENED_USERCOPY/SW_TTBR0_PAN 全关，mitigations=off（首启写入 bootargs）
- **运行时调优**：`99-perf-tuning.conf`（fq、conntrack 65536/3600s/30s、fastopen 等）
- **裁剪**：无代理/ddns/USB/存储/UPnP/WireGuard；159~197 包已贴地（kmod-dummy←hnat-detect、kmod-ifb←eqos 为真依赖）

## 刷机矩阵

| 场景 | 6.6 | 6.12 |
|---|---|---|
| 系统内 sysupgrade | `sysupgrade.bin` | `sysupgrade.itb` |
| U-Boot web（192.168.1.1）直接喂 | ❌ tar 不认 | ✅ itb |
| web 先喂 initramfs 再系统内刷 | `initramfs-kernel.bin` | `initramfs-recovery.itb` |

跨线（6.6↔6.12）刷不保留配置。产物在 `<树>/bin/targets/mediatek/filogic/`。

## 构建

```sh
just build66 / build612   # 全量构建
just smoke66 / smoke612   # 冒烟 = 树内全新编译 dnsmasq（验工具链+热路径参数）
just clean66 / clean612   # 清构建产物（容器内执行！build_dir 属主是容器映射 uid）
just builder              # 重建构建器镜像（自包含，FROM ubuntu:24.04，现行 tag v3）
```

- 前置：docker（rootless）+ just；`dl/`、`staging_dir/`（工具链）跨 clean 保留
- 改全局 CFLAGS/内核配置后必须 `clean` 再 build：OpenWrt 不会因 flag 变化自动重编
- 验证参数是否真生效用 `V=s`（默认日志无逐条 gcc 行）

## 配置契约与坑（历史踩过，勿再踩）

1. `CONFIG_KERNEL_*` 通道：根 .config 里这些行会**原样覆盖**目标内核配置——动内核配置先 grep 这条通道
2. `make defconfig` 会重置字符串符号和 select 回写：先 defconfig，后追加覆盖，再构建
3. 6.6 专属编译契约：mtk_eth_soc 基础构建期引用 HNAT 符号 → `NET_MEDIATEK_HNAT=m` + kmod-ipt-nat/kmod-ipt-core/kmod-nf-nat 是"死但必要"保留（运行期无人调用）
4. MTK 闭源驱动补丁走 `patches-7673/`（tarball 解包机制），不是改 `src/`（clean 即蒸发）
5. KALLSYMS 暂留（排障期）；真机跑稳后再关
6. turboacc 的 `global.set` 只管 LuCI 显示，init 不看它——HNAT 实际开机即启用

## 记录

八轮优化全过程（裁剪清单、BBRv3 移植、zstd、KERNEL_ 通道清扫、分层参数、BBR 覆盖修复）见各树 `README-slim.txt`；`archive/` 存 21.02 基线与官方 defconfig 参考。
