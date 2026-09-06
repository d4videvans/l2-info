# sources/rtnl/empty-bridge-generic

Synthetic contract fixture for D46/R4. It is deliberately **not** described as
a hardware capture.

The generic RTM_GETLINK shape (`linkinfo.type: "bridge"`) is based on the
2026-09-04 x86/64 OpenWrt 25.12.5 probe, which verified that ordinary software
bridges identify themselves this way and that the AF_BRIDGE view does not carry
`linkinfo` there. The specific case exercised here — a bridge present in the
generic dump while the AF_BRIDGE dump has no rows — has not yet been captured
on live hardware.

The fixture pins the architectural consequence of D46: bridge existence comes
from the bridge device's own link kind, not from having a member port. It proves
the reader's behavior for that input shape; a live empty-bridge probe is still
required before claiming the edge case verified on OpenWrt hardware.
