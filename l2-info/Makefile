# SPDX-License-Identifier: Apache-2.0
#
# Backend package: the assembler, the ubus surface, and the one core reader.
# No LuCI dependency: usable on a headless device via `ubus call l2-info
# snapshot`, and reusable by other tooling (docs/decisions.md D4).

include $(TOPDIR)/rules.mk

PKG_NAME:=l2-info
PKG_VERSION:=0.1
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=

include $(INCLUDE_DIR)/package.mk

define Package/l2-info
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Routing and Redirection
  TITLE:=Layer 2 address, port and VLAN inspection
  DEPENDS:=+rpcd-mod-ucode +ucode-mod-fs +ucode-mod-rtnl +ucode-mod-ubus
  PKGARCH:=all
endef

define Package/l2-info/description
Reads this device's bridge forwarding database, port and VLAN membership and
neighbour tables, and returns one consistent snapshot over ubus. Declares what
it could not see rather than returning an empty result. No daemon, no stored
state, nothing polled.
endef

define Build/Compile
endef

define Package/l2-info/install
	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_DATA) ./files/usr/share/rpcd/ucode/l2-info $(1)/usr/share/rpcd/ucode/l2-info
	$(INSTALL_DIR) $(1)/usr/share/l2-info
	$(INSTALL_DATA) ./files/usr/share/l2-info/assemble.uc $(1)/usr/share/l2-info/assemble.uc
	$(INSTALL_DIR) $(1)/usr/share/l2-info/readers
	$(INSTALL_DATA) ./files/usr/share/l2-info/readers/rtnl.uc $(1)/usr/share/l2-info/readers/rtnl.uc
endef

# rpcd only scans its ucode directory at startup, so a new or changed backend
# needs a restart to be visible.
define Package/l2-info/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/rpcd reload >/dev/null 2>&1
exit 0
endef

$(eval $(call BuildPackage,l2-info))
