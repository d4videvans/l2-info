# SPDX-License-Identifier: Apache-2.0
#
# View package: the LuCI page, its menu entry and its read-only ACL.
# The backend is a separate package (docs/decisions.md D4).

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for l2-info
LUCI_DESCRIPTION:=Look up which MAC addresses are on which ports and VLANs on \
this device, from a snapshot taken on request.
LUCI_DEPENDS:=+luci-base +l2-info
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0
PKG_VERSION:=0.1
PKG_RELEASE:=1

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
