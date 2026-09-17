# 360t7m-immortalwrt-slim

> 给 Qihoo 360T7M（MT7981B）的深度定制固件：把社区原版砍掉三分之一，
> 在供应商内核上跑通主线级 BBRv3 与全链路硬件卸载，编译参数逐包分层——
> 十七轮优化，每一项都有构建日志和产物哈希背书。

两条内核线并行维护，同一套改动在两棵树上对齐：

| | 6.6 稳定线 | 6.12 新线 |
|---|---|---|
| 底座 | ImmortalWrt 24.10 | ImmortalWrt 25.12（APK 时代） |
| 内核 | 6.6.133 + mt_wifi 7.6.6.1 | 6.12.103 + mt_wifi 7.6.7.3 |
| 软件包 | 161 | 159 |
| 固件体积 | 12.93MB | 15.46MB |
| sha256 | 见[哈希与复现性](#哈希与复现性) | 同上 |

**目录** — [机器与红线](#机器与红线) · [成绩单](#成绩单) · [刷机](#刷机) ·
[U-Boot 引导器](#u-boot-引导器) · [预置](#预置光猫路由模式下的-ipv6-与内网穿透) ·
[构建](#构建) · [自动化](#自动化) · [代码来源](#代码来源与致谢) · [文档](#文档)

---

## 机器与红线

MT7981B 双核 A53 @1.3GHz · 内存改装 512M · 128M NAND + 108M 大分区社区 U-Boot · 全千兆无 USB。

> ⛔ **改装机红线**：官方 `preloader.bin` / `bl31-uboot.fip` 按 **256M DDR3 时序** 编译，
> 改装机（512M）刷了**变砖**，永远不要碰。这两个文件出现在本仓库 6.12 树的
> `bin/targets/` 里（6.6 树不产出），顺手刷错就是它。

## 已结案：5G 封顶 40MHz 与 SSID 频段错位（同根因，2026-09-17）

**真凶：`CONFIG_MTK_DEFAULT_5G_PROFILE=y`，关闭即愈（`a83e01bc`）。** 关闭后
5G 直接以 HE160 起网（LuCI Bitrate 2401 Mbit/s = 2×2 HE160 满速率）。本节早先
版本记载的排除链及其结论（"裁决点在驱动内部的信道带宽能力表"）**作废**。

### 机制：mt_wifi 与用户态的顺序契约矛盾

- 开着该开关时，驱动按 **(5G;2G)** 解释 l1profile 的 `profile_path` /
  `main_ifname`：`rt_channel.c:3012` 注释明说；`multi_profile_check()` 把
  buf1 取为第二个 token；`multi_profile_merge_5g_only(data, buf2, buf1, …)`
  故意换序；`rt_profile.c` 的 `l1set_ifname()` 让先初始化的 5G band 抢走 `ra0`。
- 而 hanwckf wifi-profile 包按规范模板 **(2G;5G)** 写 `l1profile.dat`（驱动
  自带 INDEX3 模板同序），mtwifi-cfg-ucode / UCI / LuCI 也按 `ra0=2G` 假设。

于是 band↔profile↔netdev 名整体交叉：UCI 的 2G radio 绑到 ra0（驱动里实为
5G band），LuCI 显示「2.4G SSID 挂在 5G 信道」，内核狂刷 `MlmeEnqueueForRecv
orig_wdev(0/x)…msg_recv_wdev(1/y)`，且 5G band 吃到交叉后的配置，无论请求
HE80/HE160 都落到 40 —— 早先那条「5G 上限只有 40MHz」由此而来。

### 实测（360T7M 512M，2026-09-17）

| | 关闭前（干净刷入 sysupgrade -n 后 100% 复现） | 关闭后 |
|---|---|---|
| ra0（UCI=2G） | "ImmortalWrt-5G" @ ch56/5G | "ImmortalWrt-2.4G" @ ch10/2.4G |
| rax0（UCI=5G） | "ImmortalWrt-2.4G" @ ch13/2.4G，HE40 | "ImmortalWrt-5G" @ ch52/5G，**HE160** |
| 跨 band 内核刷屏 | 1074 条+ | 0 |

交叉佐证：/rom 自带的 `/etc/wireless/mediatek/DBDC_card0.dat`（驱动写的合并
导出，只写不读）字段顺序自相矛盾——`WirelessMode=17;16`（5G 在前）而
`VHT_BW=0;2`（2G 在前）。「wifi reload 不重读 dat」的现象依然成立。

### 前次排除链为何被误导

先前所有实验都在**交叉态**系统上做：「band 互换后 5G 仍 40」「VHT160 落到
VHT40」观察到的 40，源头是交叉配置给 5G band 的带宽封顶，而非信道能力表。
教训：多层命名/配置映射疑似错位时，先核对三方（UCI ↔ l1profile/dat ↔ 驱动
iwinfo）逐 band 对齐，再做变量隔离。

仍然成立的坑：

- `iwinfo_mtk.c` 的 `mtk_get_htmodelist()` 对任何 `band=5g` **无条件**列出
  HE160，与实际能力无关 —— 据此"补回 160 选项"的 `d867492a` 已被 `47d4f11a`
  revert，该 revert 依然正确。
- `config_he.c` 的 `wlan_config_get_he_bw()` 2G-AX 位钳制与本案无关。

另：上游 hanwckf / zheshifandian 均默认带 `DEFAULT_5G_PROFILE=y`，大概率同样
带病，值得报。宿主侧实测某 USB 网卡对非关联 BSS 的扫描结果会占位符化（BSSID
统一 `00:01:02:…`、频率统一 2417 MHz）——SSID/信号可信，BSSID/信道不可信，
别拿它当信道判据。

## 成绩单

相对社区原版 full 固件：

| 项 | 原 full 版 | 本项目 | 怎么做到的 |
|---|---|---|---|
| 固件体积 | 17.2MB | **12.93MB / 15.46MB** | 十七轮裁剪 + zstd-19 squashfs |
| 软件包数 | 306 | **161 / 159** | USB/存储/代理/DDNS/打印/限速全栈清退，每个幸存包反查过依赖 |
| 拥塞控制 | BBRv1 | **BBRv3 + fq pacing** | CachyOS 官方回移植（6.6/6.12 两版），内建默认 |
| NAT 转发 | 软转发 | **硬件卸载** | vendor HNAT（有线）+ WHNAT/WARP（无线）+ fullcone |
| 编译参数 | 全树一刀切 | **逐包分层** | 热路径 -O2+LTO，冷路径 -Os，`-mcpu=cortex-a53`，全二进制 sstrip |
| 内核杂税 | 服务器级默认 | **归零** | cgroups/MPTCP/io_uring/swap/BPF/加固项全部关闭，mitigations=off |

顺带修了两个"设了等于没设"的社区级 bug：turboacc 每次开机把拥塞控制覆盖回 cubic；
BBRv3 设了却因内核缺 `sch_fq` 而没有 pacing 队列。

IPv6 透传与内网穿透（含 UPnP）按实际组网场景做了预置，见[预置](#预置光猫路由模式下的-ipv6-与内网穿透)。

## 刷机

**真机验证过的完整流程**（360T7M 改装 512M，2026-09-16 实测；三步顺序不能省）：

| 步 | 做什么 | 为什么 |
|---|---|---|
| 0 | **更新 U-Boot**：failsafe → `http://192.168.1.1/uboot.html` → 选 `mt7981_360t7-fip-fixed-parts.bin` | 旧版 U-Boot（实测那台是 2024-01 的构建）**没有 `/initramfs.html` 路由**，也认不了新格式；这一步是后面两步的前提 |
| 1 | **喂 initramfs**：`http://192.168.1.1/initramfs.html` → 选 `…-initramfs-recovery.itb` → 点 **Boot** | 零写入。内存系统起好后指示灯**由红转绿**（`led-running`） |
| 2 | **在内存系统里刷固件**：LuCI → 系统 → 备份/刷写固件 → 上传 `…-squashfs-sysupgrade.itb` → **不勾"保留配置"** | 这一跳走 OpenWrt 自己的 `fit_do_upgrade`，与 U-Boot 的镜像类型分派无关，所以必成 |

⛔ **不要**在 U-Boot 的固件槽直刷 6.12 的 `sysupgrade.itb`：会被 `*** Image not supported! ***`
拒绝（该槽按镜像类型分派，FIT 不在它认的列表里）—— **实机已验证**。好消息是它报错即停，
**不写任何东西**。

| 树 | 内存系统默认 LAN | 内存系统里刷哪个 | U-Boot 固件槽直刷 |
|---|---|---|---|
| 6.6 | `192.168.6.1` | `…-squashfs-sysupgrade.bin`（tar） | 未真机验证（tar 是其原生格式：`parse_tar_image` 认 `sysupgrade-*/kernel\|root`，我们的 tar 正是这个形状） |
| 6.12 | `192.168.1.1` | `…-squashfs-sysupgrade.itb` | ⛔ 会被拒（实机验证） |

⚠️ **默认 LAN 两棵树不同**（`package/base-files/files/bin/config_generate`）：6.6 改成了
`192.168.6.1`，6.12 保留上游默认 `192.168.1.1`。6.12 的 LAN 正好与 **U-Boot failsafe** 同址 ——
不同系统占同一地址，不冲突，但要知道"现在是谁在回答"：跑固件时是固件，
要进 failsafe 必须断电**按住 RESET ≥15 秒**。

⚠️ **内存系统与要刷的固件必须同线**：6.12 的 `platform.sh` 只认 `.itb`（`fit_do_upgrade`），
6.6 只认 tar（`nand_do_upgrade`）—— 跨线在系统内刷不了。

### 先试后刷

想确认固件对不对再决定刷不刷，用 U-Boot web 恢复界面的 **Load initramfs** 通道
（`http://192.168.1.1/initramfs.html`，按钮就是 **Boot**）。

它和 `Firmware update` 槽是**两条不同的代码路径**（`failsafe/failsafe.c`）：

| 上传字段 | 类型 | 上传后做什么 |
|---|---|---|
| `firmware` | `FW_TYPE_FW` | `failsafe_write_image()` → **写 ubi** → 重启 |
| `initramfs` | `FW_TYPE_INITRD` | **跳过写盘**（`st->ret = 0`）→ `boot_from_mem()` → **直接从内存引导** |

```c
if (fw_type == FW_TYPE_INITRD)
        st->ret = 0;                          /* 不写 Flash */
...
if (upgrade_success) {
        if (fw_type == FW_TYPE_INITRD)
                boot_from_mem((ulong)upload_data);   /* 内存引导 */
        else
                do_reset(NULL, 0, 0, NULL);          /* 写盘后重启 */
}
```

**步骤**：按住 RESET 通电、保持 ≥15 秒进 failsafe（电脑网卡设固定 IP `192.168.1.100`）→
开 `http://192.168.1.1/initramfs.html` → 选上表那个 initramfs 文件 → 点 **Boot**。
NAND 一个字节都不写，不满意直接重启回原系统。

前置条件：镜像是合法 FIT（webui 会 `fdt_check_header` 校验）—— 两棵树的 initramfs 都满足。

> ⚠️ 它验证的是「**固件本身能不能起、功能对不对**」，不是「你现有配置迁移后对不对」：
> 内存系统跑的是 RAM rootfs + 镜像自带的默认配置，**读不到 NAND 上的 overlay**，
> 改配置也不落盘（页面自己会写 `System running in recovery (initramfs) mode`）。

> 另一条同样不写盘的路是串口启动菜单里的 **Load image**（`mtkload` → `bootm`），
> 但这个 defconfig 只开了 TFTP 一种来源（`Cmd/LOADB/SD/RAM` 都没开），要自己架 TFTP，不如 web 省事。

### 在 U-Boot 里刷

进 failsafe 的方式：**按住 RESET 按钮通电，保持 ≥15 秒**再松开；电脑网卡设成
**固定 IP `192.168.1.100`**，接路由器任一 LAN 口，浏览器（建议无痕）打开下表的地址。

| 你要做什么 | 用哪个文件 | 入口 |
|---|---|---|
| 更新 **U-Boot 自己**（webui） | `out/mt7981_360t7-fip-fixed-parts.bin`（**FIP**） | `http://192.168.1.1/uboot.html` → 选 FIP |
| **引导内存系统**（零写入） | `…-initramfs-{recovery.itb,kernel.bin}` | `http://192.168.1.1/initramfs.html` → **Boot** |
| 刷**固件**（6.6 的 tar） | `…-squashfs-sysupgrade.bin` | `http://192.168.1.1` → 固件槽（未真机验证） |
| 刷**固件**（6.12） | ⛔ 直刷会被拒 —— 走[上面三步流程](#刷机)的第 1、2 步 | — |
| 更新 **U-Boot 自己**（串口） | 同上，还是那个 FIP | U-Boot 控制台 `mtkupgrade fip`（走 TFTP） |

⛔ **更新 U-Boot 时千万别选** `…-bl31-uboot.fip` / `…-preloader.bin`（见[产物清单](#产物清单哪个文件归哪种机器)第 5、6 行）。
它们文件名里也有 `uboot.fip`，但那是 OpenWrt **主线**构建 + 官方 256M DDR3 时序，
改装机刷了变砖 —— 要刷的社区 FIP 在 `out/` 或 release 里，文件名是
**`mt7981_360t7-fip-fixed-parts.bin`**（没有 `bl31-` 前缀，也不是 `immortalwrt-…` 开头）。

### 安全边界：谁写哪个分区

**结论：没有任何一份「固件镜像」会写多个分区。刷固件永远只写 `ubi`；
会动到 U-Boot 的，只有你在 U-Boot 里主动选 `fip` / `bl2` 槽。**

分区布局（社区 U-Boot 的 `mtdparts`）：
`bl2`(1M) · `Nvram` · `Bdata` · `factory`(2M) · **`fip`(2M)** · `crash` · `crash_log` · `ubi_kernel` / `ubi`(固件所在)

**A. 系统内 sysupgrade** —— 两棵树都只写 ubi：

| 树 | 路径 | 依据 |
|---|---|---|
| 6.6 | `nand_do_upgrade`，`CI_UBIPART="ubi"` `CI_KERNPART="kernel"` `CI_ROOTPART="rootfs"` | `filogic/base-files/lib/upgrade/platform.sh` 的 `qihoo,360t7` 分支 |
| 6.12 | `fit_do_upgrade`：从设备树 `/chosen/rootdisk` 反查出 ubi 卷 → `CI_METHOD="ubi"` → 仍走 `nand_do_upgrade` | `package/utils/fitblk/files/fit.sh` |

镜像里也没有任何"多分区"指令：6.6 的 tar 只有 `CONTROL`（内容仅 `BOARD=qihoo_360t7`）/`kernel`/`root`；
6.12 的 ITB 元数据只有 `supported_devices` 与 `version`，没有分区字段。

**B. U-Boot 的槽位**（webui 与串口 `mtkupgrade <abbr>` 同一套）—— 来自
`board/mediatek/common/bootmenu_mtd.c` 的 `mtd_parts[]`：

| 槽位 | abbr | 写哪个分区 | 会不会顶掉 U-Boot |
|---|---|---|---|
| Firmware（webui 主页固件槽） | `fw` | **只写 `ubi`** | ❌ 不会 |
| ATF FIP（`/uboot.html`） | `fip` | `fip` 分区 | ✅ **会** —— 更新 U-Boot 自己 |
| ATF BL2 | `bl2` | `bl2` 分区 | ✅ **会** —— 更新 preloader（最危险，刷错直接不引导） |
| BL31 / BL33 of FIP | `bl31` / `bl33` | `fip` 分区内的单个组件 | ✅ 会 |

固件槽还有一层硬保护（即使种子把 `CONFIG_MTK_UPGRADE_IMAGE_VERIFY` 关掉）：
`write_firmware` → `mtd_upgrade_image()` 的目标分区写死为 `PART_UBI_NAME`，
只处理它认识的镜像类型（`IMAGE_UBI1` / `IMAGE_UBI2` / `IMAGE_TAR` / `IMAGE_RAW` / FIT），
其它一律 `*** Image not supported! ***` 不写。

**所以真正要小心的只有一件事**：在 `/uboot.html` 选文件时别选错 ——
社区版叫 `mt7981_360t7-fip-fixed-parts.bin`（可刷），
主线版叫 `immortalwrt-…-bl31-uboot.fip`（改装机刷了变砖）。

### 产物清单：哪个文件归哪种机器

**先说结论：固件镜像与内存容量无关，256M 原装机与 512M 改装机通用；
两种机器的差别只体现在引导器。**

为什么固件通用：固件 DTS 里的 `memory@40000000` 只是**占位值**，开机时会被
U-Boot 用探测到的真实容量改写（`dram_init()` 的 `get_ram_size()` →
`arch_fixup_fdt()` 重写 `/memory` 节点），所以同一份固件两边都能跑。

| 产物 | 内容 | 256M 原装机 | 512M 改装机 |
|---|---|---|---|
| `<树>/bin/targets/…/*-sysupgrade.{bin,itb}` | 固件（kernel + rootfs） | ✅ | ✅ |
| `<树>/bin/targets/…/*-initramfs-*` | 内存系统（救砖 / 先试后刷） | ✅ | ✅ |
| `out/mt7981_360t7-fip-fixed-parts.bin`¹ | **社区** FIP：BL31 + U-Boot | — | ✅ **刷这个** |
| `out/mt7981_360t7-bl2.bin`¹ | **社区** BL2（preloader） | — | 一般用不到² |
| `…-bl31-uboot.fip`³ | **OpenWrt 主线** U-Boot | ⚠️ 不建议 | ⛔ **禁止** |
| `…-preloader.bin`³ | **OpenWrt 主线** BL2 | ⚠️ 不建议 | ⛔ **禁止** |

¹ 社区 U-Boot（`just uboot` 构建，来源 `hanwckf/bl-mt798x`，按 `uboot-revision` 固定
commit）——**设备实际运行的那个**，也是 release 里附带的那两个文件。
刷写走 U-Boot 的 failsafe webui（见[上一节](#在-u-boot-里刷)）。
注意 `192.168.1.1` 是 **U-Boot failsafe 的地址**；6.12 固件的默认 LAN 也是它（6.6 是 `192.168.6.1`）—— **同址但不同系统**，别搞混谁在回答。

² FIP 里只有 BL31 + U-Boot 两个组件（解 TOC 可见 `47d4086d…`=BL31、
`d6d0eea7…`=BL33/U-Boot，随后是结束标记），**不含 BL2**；BL2 单独出文件是给
「只写 preloader 分区」的场景（修复/编程器）用的，正常刷写流程不需要。

³ **⛔ 改装机红线**：这两个是 OpenWrt 主线构建 + 官方 **256M DDR3 时序**
（6.12 用的是 `spim-nand-ddr3-1866`），改装机（512M）刷了变砖，永远不要碰。
注意**两棵树产出不同**：

- **6.6 树不产出**这两个文件（设备定义里没有 `ARTIFACT` 行）
- **6.12 树会产出**，就躺在 `bin/targets/` 里跟固件并列 —— 顺手刷错就是这个
- 两者都**不在固件 rootfs 内**（`uboot-mediatek` 只 stage 到 `STAGING_DIR_IMAGE`，
  不装进系统），所以只要不手动去刷 `bin/targets/` 下那两个，就没有误刷风险

它们对本仓库唯一的意义是「target 设备定义要求的构建产物」（种子里
`CONFIG_PACKAGE_u-boot-mt7981_qihoo_360t7=y` 与 `trusted-firmware-a-mt7981-spim-nand-ddr3*`
是强制保留项）。

- 对**改装机（512M）**：⛔ **禁止**，256M 时序直接变砖。
- 对**原装机（256M）**：也是 ⚠️ **不建议**。它会把设备上正在跑的社区 U-Boot
  顶掉，而两者分区布局不同（社区版按 108M 大分区固定 mtdparts），
  顶掉之后现有固件大概率起不来。**本仓库不提供"刷回主线 U-Boot"的路径。**

## U-Boot 引导器

设备的引导器是**社区 U-Boot（`hanwckf/bl-mt798x`）**，不是本仓库构建的那个。两者必须分清：

| | 本仓库 `package/boot/uboot-mediatek` | `hanwckf/bl-mt798x` |
|---|---|---|
| 基线 | OpenWrt 主线 U-Boot（6.6 用 2024.10，6.12 用 2025.10） | MediaTek SDK U-Boot + ATF |
| 产出去向 | 随固件打包，作**设备自带引导器的备份**（`u-boot-mt7981_qihoo_360t7` 是设备符号强制保留项） | **设备实际运行的那个** |
| 512MB 内存 | 不支持（DDR 时序按 256MB 调） | **支持** —— 时序可训 512MB 颗粒，故改装机刷它 |

因此**不要刷本仓库构建出的 `bl31-uboot.fip` / `preloader.bin`**（就是[机器与红线](#机器与红线)那条）。
若需要（重）刷社区 U-Boot：

```sh
just uboot          # 取 hanwckf/bl-mt798x（按 uboot-revision 固定 commit）并构建
just uboot-fetch    # 只取/更新源码
just uboot-status   # 查看固定 commit 与本地状态
```

产物落在 `out/`，**两个文件对应两个不同的分区，不是二选一**：

| 文件 | 内容（实测 FIP 的 TOC） | 分区 |
|---|---|---|
| `mt7981_360t7-bl2.bin` | BL2（preloader 阶段） | preloader |
| `mt7981_360t7-fip-fixed-parts.bin` | FIP：BL31 + U-Boot | FIP |

FIP 内的条目可以直接从二进制解出来（TOC 每条 40 字节，UUID 与 TF-A 头文件对得上）：
`47d4086d…` = `UUID_EL3_RUNTIME_FIRMWARE_BL31`（33,065 字节）、
`d6d0eea7…` = `UUID_NON_TRUSTED_FIRMWARE_BL33`（723,280 字节，即 U-Boot），随后是全零结束标记
—— **FIP 里并不含 BL2**，所以 BL2 才会单独出一个文件。
构建使用 `SOC=mt7981 BOARD=360t7`（官方 `build.sh` 支持的 board 名），全程容器内进行。

> ⚠️ 这份 U-Boot **不是位级可复现的**（与固件不同）：BL31 与 U-Boot 的版本串里带构建时间
> （`Built : 11:15:31, Sep 16 2026`），同一 commit 换个时间构建就有十几字节差异 ——
> 实测本地与 CI 同 commit 的两份 FIP **差 14 字节**，差异全在这两处时间戳字符串里。
> 所以确认"是不是同一份"要**比 `UPSTREAM-COMMIT`，别比哈希**。

这两份也随 **release 一起发布**（`release` workflow 里有一个独立的 `uboot` job，
见[自动化](#自动化)），附 `UPSTREAM-COMMIT` 与 `READ-ME-FIRST.txt`（写清哪个文件该刷、
以及为什么固件目录里那两个 `bl31-uboot.fip`/`preloader.bin` 绝不能刷）。
不想等 release 也可以单独取：`uboot` workflow 的 artifact，或本地 `just uboot`。

> ⚠️ 刷写引导器风险远高于刷固件，写错即变砖。相关教程见 hanwckf 的
> [mt798x uboot 使用说明](https://cmi.hanwckf.top/p/mt798x-uboot-usage)。本仓库只负责构建，不代办刷写。

## 预置：光猫路由模式下的 IPv6 与内网穿透

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

三条链缺一不可：`ra` 中继 RA、`ndp` 代理邻居、`dhcpv6` 保住中继 RA 的 M/O 位——
只配前两条时，上游若为 stateful（RA 置 M、PIO 不带 A），odhcpd 会抹掉 M/O，
LAN 设备既不能 SLAAC 也不会要 DHCPv6，一个地址都拿不到。

**UPnP 默认开启**是为内网设备自建的 tailscale：走 UPnP/NAT-PMP/PCP 拿到 IPv4 直连，
而不是长期挂在 DERP 中继上。上游包默认 `enabled=0`（每次刷机都要手点），此处改为默认开；
`secure_mode=1` 与"默认拒绝 + 仅放行 1024-65535"的 perm_rule 保持上游原样——映射只对发起请求的那台主机生效。

## 构建

```sh
just build66 / build612             # 6.6 稳定线 / 6.12 新线 全量构建
just pick66 / pick612 sysupgrade    # 取刷机镜像到 out/（或 initramfs=救砖镜像 / all）
just smoke66                        # 冒烟：树内全新编译 dnsmasq
just vm-smoke66 / vm-smoke612       # QEMU 冒烟：qemu virt 上真启动固件（见下）
just builder                        # 重建自包含构建器镜像（FROM ubuntu:24.04）
```

全量约半小时（14 核），工具链与 dl 缓存跨次复用。
并行度：核数 > 8 时**留 4 核给宿主**（14 核 → `-j10`），避免构建期间机器没法干别的；
≤ 8 核（含 CI 的 4 vCPU runner）用满，免得在 CI 上退化成 `-j1`。
想显式指定：`JOBS=$(nproc) just build66`。

构建在 rootless docker 容器内进行（镜像 v3，dpkg 集合与原镜像逐一比对一致），
新克隆即可构建，不依赖本机残留：

- `REVISION` 来自树内 `revision` 文件（入库），不再依赖未入库的 `archive/`
- feeds 在 `feeds.conf.default` 里用 `^sha` 固定；`feeds/` 不入库，首次构建自动按固定 sha 拉取
  （只保留 `packages` 与 `luci` 两条——`routing`/`telephony`/`video` 对本目标 0 贡献，见第十四轮）
- in-tree 包的 mtime 会被钉到 `version.date` —— 否则 in-tree luci 包的版本号取自
  checkout 时刻，产物不可复现（根因与实测见[哈希与复现性](#哈希与复现性)）
- 因此同一提交在同一构建环境快照下重建，产物 sha256 一致（`release` workflow 每次发布前
  都用 `sha256sum -c` 双构建核对，不一致即拒绝发布；本地干净克隆也复核过）

### 哈希与复现性

核心不变量是「**一个提交 + 一个种子 = 一个产物**」：`release` workflow 每次发布前都先
`just distclean` 再**重建一次**，用 `sha256sum -c` 比对，不一致即拒绝发布。

| 提交 | 6.6 `sysupgrade.bin` | 6.12 `sysupgrade.itb` | 怎么验证的 |
|---|---|---|---|
| `e01999ad`（第十四轮） | `b3cffb37…` · 12,933,916 B · 161 包 | `84cd39bf…` · 15,458,568 B · 159 包 | 本地干净克隆 + CI 双构建，字节一致 |
| `5a9c72bf`（tag `v2026.09.16`） | `37595ded…` | `0af41b99…` | 见该 release 的 `SHA256SUMS` |

> ⚠️ **实测到过一个破坏可复现性的 bug（已修）**：同一次 CI run 里两个 job 构建**同一个提交**，
> `reproducible` 得出 `ebed88a2…`、`release` 得出 `37595ded…` —— 两次都不算错，但**互不相等**。
> 根因：容器只挂载了 tree 目录（`.git` 在仓库根、没进容器），in-tree 的 luci 包没有 git 可用，
> `luci.mk` 的 `findrev` 于是回退到「取包源码最新的 mtime」当版本号
> （`0.<日期>.<当日秒数>`）—— 版本号被 **checkout 时刻** 决定，自然每次 checkout 都不同。
> 修法：`justfile` 在构建前把 in-tree 包的 mtime 钉到 `version.date`（= SOURCE_DATE_EPOCH 锚点）。
> 复现/确认：同一个包在 mtime=08:00:00Z 与 20:00:00Z 两种"checkout"下，
> **修前**得到 `0.260916.28800` / `0.260916.72000`，**修后**都是 `0.260913.66371`。

> ⚠️ 核对哈希必须用**干净克隆**（无 `staging_dir`）。在工作区增量构建，工具链是早先编译的
> （可能早于 `version.date` 引入 SOURCE_DATE_EPOCH 的时刻），产物会与干净克隆不同。
> 要核对就先 `just distclean66` 删掉 `staging_dir` 再构建。

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

两树实测均 **17/17 断言全通过**（6.6 与 6.12 同一套哨兵断言）。实现上有几处必须照做
（脚本内已注释，改动前先读）：

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

## 自动化

四条 workflow，均可用 `workflow_dispatch` 手动触发：

| workflow | 触发 | 作用 |
|---|---|---|
| `build` | push/PR | 干净 runner 上全量构建两树，产出 artifact + SHA256SUMS。**这是下面几条的门禁** |
| `upstream-sync` | 每日 | 探测上游（padavanonly / zheshifandian），把我们的改动 rebase 到新上游，开 PR；冲突则开 issue |
| `feeds-update` | 每周一 | 把 feeds 的 `^sha` 推进到分支 HEAD，构建验证后开 PR |
| `release` | tag `v*` / 手动 | 两树全量构建 → **重建比对哈希**（不可复现则拒绝发布） → GitHub Release（含固件 + **社区 U-Boot** + 各自 SHA256SUMS） |
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
| **U-Boot + ATF** | [`hanwckf/bl-mt798x`](https://github.com/hanwckf/bl-mt798x) | 设备实际运行的引导器；见 [U-Boot 引导器](#u-boot-引导器) |
| BBRv3 | CachyOS（Peter Jung） | 官方回移植补丁，源码内保留 `From:` 签名 |
| 其余 feed 包 | ImmortalWrt / OpenWrt 官方 feed | 按 `^sha` 固定，见 `feeds.conf.default` |

我们相对上游所做的改动，可随时导出核对（这也是 `upstream-sync` 的机制）：

```sh
git clone <上游> /tmp/up && cd /tmp/up && git checkout $(cat <树>/base-upstream)
# 树目录内容叠加到该基线之上，即为我们的全部改动
```

## 文档

- [`mt798x-6.6/README-slim.txt`](mt798x-6.6/README-slim.txt) — 十七轮优化全过程：裁剪清单、BBRv3 移植、
  KERNEL_ 通道清扫、分层参数、BBR 覆盖 bug 修复、fq pacing 补装、QEMU 冒烟
- [`mt798x-6.12/README-slim.txt`](mt798x-6.12/README-slim.txt) — 新线移植记录（PRECAL/netif_rx 补丁、
  mtkhnat 契约差异）、UPnP 栈补齐与同步的对齐策略、QEMU 冒烟实测
