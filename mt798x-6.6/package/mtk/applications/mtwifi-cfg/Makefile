#
# This is free software, licensed under the GNU General Public License v2.
#


include $(TOPDIR)/rules.mk

PKG_NAME:=mtwifi-cfg
PKG_LICENSE:=GPL-2.0+
PKG_VERSION:=1
PKG_RELEASE:=2

include $(INCLUDE_DIR)/package.mk

# 上游漏声明的三个硬依赖，缺一即 mtwifi_cfg 起不来（WiFi 拉不起）：
#   +lua              mtwifi_cfg / l1util 的 shebang 是 #!/usr/bin/lua
#   +luci-lib-nixio   mtwifi_cfg / l1dat_parser.lua 里 require("nixio")
#   +lua-cjson        require("cjson")
define Package/mtwifi-cfg
  SECTION:=MTK Properties
  CATEGORY:=MTK Properties
  SUBMENU:=Applications
  TITLE:=mtwifi configure scripts for mt798x
  DEPENDS:=+iwinfo +wifi-dats +lua-cjson +datconf-lua +lua +luci-lib-nixio
endef

define Package/mtwifi-wapp
	SECTION:=MTK Properties
	CATEGORY:=MTK Properties
	SUBMENU:=Applications
	TITLE:=mtwifi wapp scripts for mt798x
	DEPENDS:=+mtwifi-cfg
endef

define Build/Compile
endef

define Package/mtwifi-cfg/install
	$(INSTALL_DIR) $(1)/sbin $(1)/usr/lib/lua
	$(INSTALL_DIR) $(1)/lib/netifd/wireless/ $(1)/lib/wifi/

	$(INSTALL_DIR) $(1)/etc/hotplug.d/net/

	$(INSTALL_BIN) ./files/netifd/mtwifi.sh $(1)/lib/netifd/wireless/
	$(INSTALL_BIN) ./files/mtwifi.sh $(1)/lib/wifi/
	$(INSTALL_BIN) ./files/mtwifi-cfg/mtwifi_cfg $(1)/sbin/
	$(INSTALL_BIN) ./files/mtwifi-cfg/inspect.lua $(1)/usr/lib/lua/
	$(INSTALL_BIN) ./files/mtwifi-cfg/mtwifi_defs.lua $(1)/usr/lib/lua/
	$(INSTALL_BIN) ./files/mtwifi-cfg/mtwifi_utils.lua $(1)/usr/lib/lua/
	$(INSTALL_BIN) ./files/l1util/l1util $(1)/sbin/
	$(LN) l1util $(1)/sbin/l1dat
	$(INSTALL_BIN) ./files/l1util/l1dat_parser.lua $(1)/usr/lib/lua/
	$(INSTALL_DATA) ./files/hotplug/10-mtwifi-detect $(1)/etc/hotplug.d/net/
endef

define Package/mtwifi-wapp/install
	$(INSTALL_DIR) $(1)/sbin
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_DIR) $(1)/etc/map/
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface/

	$(INSTALL_BIN) ./files/wapp/libs/libcrypto.so.1.1 $(1)/usr/lib/
	$(INSTALL_BIN) ./files/wapp/libs/libssl.so.1.1 $(1)/usr/lib/
	$(INSTALL_BIN) ./files/wapp/100-startwapp $(1)/etc/hotplug.d/iface/
	$(INSTALL_BIN) ./files/wapp/startwapp.sh $(1)/sbin/
	$(INSTALL_BIN) ./files/wapp/bs20 $(1)/sbin/
	$(INSTALL_BIN) ./files/wapp/wapp $(1)/sbin/
	$(INSTALL_BIN) ./files/wapp/wappctrl $(1)/sbin/
	$(INSTALL_BIN) ./files/wapp/setbssid $(1)/sbin/
	$(INSTALL_BIN) ./files/wapp/steeringsta $(1)/sbin/
	$(INSTALL_DATA) ./files/wapp/mapd_cfg $(1)/etc/map/
	$(INSTALL_DATA) ./files/wapp/wapp_ap.conf $(1)/etc/
	$(INSTALL_DATA) ./files/wapp/wapp_ap_ra0.conf $(1)/etc/
	$(INSTALL_DATA) ./files/wapp/1905d.cfg $(1)/etc/map/
endef

$(eval $(call BuildPackage,mtwifi-cfg))
$(eval $(call BuildPackage,mtwifi-wapp))
