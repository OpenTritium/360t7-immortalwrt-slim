include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for Easy QoS
# 上游在这里声明了 +wget-ssl，但本包全树（init / eqos 脚本 / hotplug / uci-defaults）
# 无任何一处调用 wget。属死依赖：它会把 wget-ssl（~190KB 压缩）+ libpcre2 + zlib
# 拖进固件。已移除（第十四轮）。
LUCI_DEPENDS:=+tc +kmod-sched-core +kmod-ifb +ebtables-legacy-utils +ebtables-legacy  @!PACKAGE_luci-app-eqos

PKG_MAINTAINER:=Jianhui Zhao <jianhuizhao329@gmail.com>
PKG_NAME:=luci-app-eqos-mtk

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
