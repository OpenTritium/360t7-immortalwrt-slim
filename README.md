# 360t7m-immortalwrt-slim

Qihoo 360T7M（MT7981B，512M 内存改装，108M 大分区社区 U-Boot）自编译固件工作区。
双内核线并行，均为裁调版：无代理/ddns 组件、BBRv3 内建默认且开机不被覆盖、
分层编译参数（热路径 -O2+LTO / 冷路径 -Os）、无加固税、zstd-19 squashfs、
连接参数调优。详见各树 `README-slim.txt`。

| 树 | 底座 | 内核 | 无线 | 产物 | 状态 |
|---|---|---|---|---|---|
| `mt798x-6.6`  | ImmortalWrt 24.10 | 6.6.133 | mt_wifi 7.6.6.1 + HNAT | sysupgrade.bin | 稳定基线（197 包，14.75MB） |
| `mt798x-6.12` | ImmortalWrt 25.12 | 6.12.103 | mt_wifi 7.6.6.1 + mtkhnat | sysupgrade.itb | 新线（159 包，16.5MB） |

## 常用命令

```sh
just build66      # 构建 6.6 稳定基线
just build612     # 构建 6.12 新线
just smoke66      # 冒烟：树内全新编译 dnsmasq（验证工具链 + 热路径编译参数）
just clean612     # 清理构建产物（容器内执行，保留工具链缓存）
just builder      # 重建 docker 构建器镜像（自包含，FROM ubuntu:24.04）
```

产物输出在 `<树>/bin/targets/mediatek/filogic/`。
`archive/` 存放历史遗留配置（21.02 基线、官方 defconfig 参考）。
