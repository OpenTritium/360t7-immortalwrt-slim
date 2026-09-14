# 360T7M 固件工作区

| 树 | 底座 | 内核 | 无线 | 产物 | 状态 |
|---|---|---|---|---|---|
| `mt798x-6.6`  | ImmortalWrt 24.10 | 6.6.133 | mt_wifi 7.6.6.1 + HNAT | sysupgrade.bin | 稳定基线（197 包，15.44MB） |
| `mt798x-6.12` | ImmortalWrt 25.12 | 6.12.103 | mt_wifi 7.6.6.1 + mtkhnat | sysupgrade.itb | 新线（175 包） |

两树均为精简纯净版：无代理/ddns 组件、BBRv3 内建默认、-O2 无加固、
zstd-19 squashfs、连接参数调优。详见各树 `README-slim.txt`。

## 常用命令

```sh
just build66      # 构建 6.6 稳定基线
just build612     # 构建 6.12 新线
just smoke66      # 冒烟：快速验证工具链
just clean612     # 清理构建产物（保留工具链缓存）
just builder      # 重建 docker 构建器镜像
```

产物输出在 `<树>/bin/targets/mediatek/filogic/`。
`archive/` 存放历史遗留配置（21.02 基线、官方 defconfig 参考）。
