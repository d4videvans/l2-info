# SPDX-License-Identifier: Apache-2.0
#
# View package: the LuCI page, its menu entry and its read-only ACL.
# The backend is a separate package (docs/decisions.md D4).

include $(TOPDIR)/rules.mk

LUCI_TITLE:=MAC & VLAN Lookup
LUCI_DESCRIPTION:=Look up which MAC addresses are on which ports and VLANs on \
this device, from a snapshot taken on request.
LUCI_DEPENDS:=+luci-base +l2-info

# Public test candidates can differ only in LuCI code. Use explicit package
# metadata so an installed LuCI package identifies the candidate instead of
# relying on luci.mk's source-revision-derived version.
PKG_VERSION:=0.1.0
PKG_RELEASE:=3

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=David Evans <d@videvans.com>

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
