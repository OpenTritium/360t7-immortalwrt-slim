# SPDX-Identifier-License: GPL-3.0-only
#
# Copyright (C) 2018 Lean <coolsnowwolf@gmail.com>
# Copyright (C) 2019-2022 ImmortalWrt.org

include $(TOPDIR)/rules.mk

PKG_LICENSE:=GPL-3.0-only

LUCI_TITLE:=LuCI support for MTK HNAT
# 只声明真正用到的依赖：init 脚本只操作 HNAT debugfs 与 sysctl，
# 不装 ss/iproute2，inet-diag/netlink-diag 两个 kmod 无运行期消费者。
LUCI_DEPENDS:= \
	+kmod-mediatek_hnat +kmod-tcp-bbr \
	@!PACKAGE_luci-app-turboacc
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
