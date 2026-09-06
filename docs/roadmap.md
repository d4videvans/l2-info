# Roadmap

This roadmap records ideas that are useful enough to preserve but are **not part of the v0.1.0-rc1 scope**. Items here are intentionally weaker commitments than the current decision register: they should only become implementation work when there is evidence that the extra complexity is justified.

## Opt-in active host/IP/name enrichment

A future version could offer a checkbox or equivalent per-snapshot option such as **Discover IP addresses and names**.

The default snapshot would remain exactly as it is now: passive, read-only observation of the bridge/FDB state, existing IPv4/IPv6 neighbour entries, DHCP/local name sources and other state already known by the OpenWrt device.

When explicitly selected for one snapshot, an enrichment pass could attempt to discover additional identity information for MAC addresses before returning the completed snapshot.

Possible shape:

- keep active discovery **off by default** and require an explicit user action for each enriched snapshot;
- retain the existing passive IPv4 and IPv6 neighbour-table reads;
- perform bounded IPv4 neighbour discovery on directly connected networks, then re-read the neighbour table so newly learned MAC-to-IP mappings can be included;
- treat IPv6 active discovery as best-effort rather than attempting to scan an IPv6 prefix;
- attempt reverse-DNS/PTR resolution for discovered IP addresses using the router's normal resolver;
- preserve DHCP/local host names separately from DNS/PTR names when both exist rather than silently choosing one source as authoritative;
- allow more than one IPv4/IPv6 address and, if the schema is extended, more than one independently sourced name for a MAC;
- expose discovery duration/status so users can distinguish a completed passive snapshot from an active enrichment attempt that was skipped, bounded, partial or timed out;
- apply hard limits to address count, concurrency and elapsed time so a broad local prefix cannot turn one snapshot into an uncontrolled network scan;
- generate local network traffic only when the option is selected; never introduce automatic polling, background discovery or persistent state.

### Design questions to resolve before implementation

1. **API shape.** The current `snapshot` ubus method deliberately takes no arguments. An enrichment option would need either an optional argument (for example `{"discover_hosts":true}`) or a separate method while preserving the ordinary no-argument call unchanged.
2. **Name model.** The current schema has a single `name.hostname` fact. DHCP/local names and DNS/PTR names may differ legitimately, so an implementation should not make one silently win.
3. **IPv4 bounds.** Decide a defensible maximum prefix/address count and timeout policy rather than assuming every directly connected subnet is safe to probe in full.
4. **IPv6 behaviour.** Define useful, standards-consistent best-effort discovery without presenting an unscannable `/64` as a completeness failure.
5. **Status/provenance.** Active discovery should remain explicit in the snapshot's scope/status information, including what was attempted and why it may have been incomplete.
6. **Testing and hardware evidence.** Add deterministic fixture coverage for success, timeout, skipped-large-prefix, DNS failure and mixed IPv4/IPv6 cases before enabling the feature on real hardware.

The intended value is narrowly aligned with the existing tool: after locating a MAC on a port/VLAN, help the user answer **"what device is that?"** when the router can safely learn more. It should not turn `l2-info` into a general network scanner, inventory system or monitoring daemon.

## Roadmap discipline

Other future ideas should be added here only when they fit the same principles:

- observe before configuring;
- prefer evidence from real hardware over target allowlists or speculative readers;
- make expensive or active operations explicit and bounded;
- preserve unknown/partial states instead of manufacturing completeness;
- avoid background polling or persistent inventory unless the project scope is deliberately reconsidered.
