// SPDX-License-Identifier: Apache-2.0
//
// l2-info reader: rtnl
//
// Kernel bridge and neighbour tables via netlink. The one reader shipped with
// the core, loaded through the same discovery path as any third party one.
//
// Contract: docs/readers.md. This file emits `subject` and `attrs` only: no
// `derived`, no `source`, no counts, no joins, no inference. All of those
// belong to the assembler (D32).

'use strict';

// ucode-mod-rtnl does not export RTEXT_FILTER_*; see linux/if_link.h.
const RTEXT_FILTER_BRVLAN_COMPRESSED = 0x04;

// linux/if_bridge.h - struct bridge_vlan_info flags.
const BRIDGE_VLAN_INFO_PVID     = 0x02;
const BRIDGE_VLAN_INFO_UNTAGGED = 0x04;

function macfmt(mac) {
	let h = lc(replace(mac ?? '', /[^0-9A-Fa-f]/g, ''));

	if (length(h) != 12)
		return null;

	let out = [];

	for (let i = 0; i < 12; i += 2)
		push(out, substr(h, i, 2));

	return join(':', out);
}

// iproute2 prints state and flags as one bare-token stream in the text form of
// `bridge fdb show`, and that is the vocabulary the format registers (D19).
// Order and spelling follow bridge/fdb.c's fdb_print_flags() then state_n2a().
function fdb_flags(nl, state, flags) {
	let out = [];
	let c = nl.const;

	if (flags & c.NTF_SELF)        push(out, 'self');
	if (flags & c.NTF_ROUTER)      push(out, 'router');
	if (flags & c.NTF_EXT_LEARNED) push(out, 'extern_learn');
	if (flags & c.NTF_OFFLOADED)   push(out, 'offload');
	// NTF_MASTER is a request flag used when adding an entry and does not
	// come back on a dump; the `master <name>` in a `bridge fdb show` line is
	// NDA_MASTER, which is fdb.bridge here. Kept for completeness against
	// fdb.c, and untested because nothing observed sets it (D42).
	if (flags & c.NTF_MASTER)      push(out, 'master');
	if (flags & c.NTF_STICKY)      push(out, 'sticky');

	if (state & c.NUD_PERMANENT)
		push(out, 'permanent');
	else if (state & c.NUD_NOARP)
		push(out, 'static');
	else if (state & c.NUD_STALE)
		push(out, 'stale');

	return out;
}

// Single seam for every netlink read, so a failure is never indistinguishable
// from an empty table (D18) and so fixture replay is total. ucode-mod-rtnl's
// multipart request result stays null when a dump completes successfully with
// zero valid rows; nl.error() is the independent error channel. Null plus no
// error therefore means an empty successful dump, not failure.
function dump(nl, cmd, payload) {
	let rows = nl.request(cmd, nl.const.NLM_F_DUMP, payload);
	let err = nl.error();

	if (err != null)
		return { error: err };

	return { rows: rows ?? [] };
}

// ---------------------------------------------------------------- collections

// Bridge identity and bridge membership are different facts and come from two
// views of RTM_GETLINK (D46). The generic dump exposes IFLA_INFO_KIND as
// linkinfo.type and therefore identifies a bridge from the device itself. It
// also reports the bridge link's own address. The AF_BRIDGE dump supplies port
// membership and live VLAN membership; on current x86 OpenWrt it deliberately
// has linkinfo == null and a bridge may appear as its own master, so master
// references are not used to establish identity.
function read_links(nl) {
	let generic = dump(nl, nl.const.RTM_GETLINK, {});

	if (generic.error)
		return { error: `generic link dump: ${generic.error}` };

	let bridges = {}, bridge_addresses = {};

	for (let l in generic.rows) {
		let name = l.ifname ?? l.dev;

		if (!name || l.linkinfo?.type != 'bridge')
			continue;

		bridges[name] = 0;

		let address = macfmt(l.address);

		if (address != null)
			bridge_addresses[name] = address;
	}

	let d = dump(nl, nl.const.RTM_GETLINK, {
		family: nl.const.AF_BRIDGE,
		ext_mask: RTEXT_FILTER_BRVLAN_COMPRESSED
	});

	if (d.error)
		return { error: `AF_BRIDGE link dump: ${d.error}` };

	let ports = [], seen = {};

	for (let l in d.rows) {
		let name = l.ifname ?? l.dev;

		if (!name || seen[name])
			continue;

		seen[name] = true;

		let vlans = [], flag_text = [], untagged = [], pvid = null;

		for (let v in l.af_spec?.bridge?.bridge_vlan_info ?? []) {
			let start = v.vid;
			let end = (v.vid_end != null && v.vid_end > v.vid) ? v.vid_end : v.vid;

			// `bridge -j vlan show` renders these as array elements "PVID"
			// and "Egress Untagged"; the text form prints them space
			// joined, which is the registered shape.
			let text = [];

			if (v.flags & BRIDGE_VLAN_INFO_PVID)
				push(text, 'PVID');

			if (v.flags & BRIDGE_VLAN_INFO_UNTAGGED)
				push(text, 'Egress Untagged');

			let t = join(' ', text);

			for (let vid = start; vid <= end; vid++) {
				push(vlans, vid);
				push(flag_text, t);

				if (v.flags & BRIDGE_VLAN_INFO_PVID)
					pvid = vid;

				if (v.flags & BRIDGE_VLAN_INFO_UNTAGGED)
					push(untagged, vid);
			}
		}

		push(ports, {
			name,
			master: l.master,
			vlans,
			flag_text,
			untagged,
			pvid,
			carrier: l.carrier,
			address: macfmt(l.address)
		});
	}

	for (let p in ports) {
		if (!p.master || p.master == p.name)
			continue;

		// AF_BRIDGE should only name a bridge as master. If the two dumps
		// disagree, treating the reference as bridge identity would recreate
		// the inference D46 removes; declare the inconsistent read instead.
		if (bridges[p.master] == null)
			return {
				error: `AF_BRIDGE link '${p.name}' names master '${p.master}', which the generic link dump did not identify as a bridge`
			};

		bridges[p.master]++;
	}

	return { ports, bridges, bridge_addresses };
}

function port_rows(links) {
	let rows = [];

	for (let p in links.ports) {
		// A bridge is not a port of itself. Bridge identity comes from the
		// generic link kind, so this remains true whether AF_BRIDGE gives the
		// bridge no master, itself as master, or omits an empty bridge entirely.
		if (links.bridges[p.name] != null)
			continue;

		let attrs = { 'topo.port': p.name };

		if (p.master != null)
			attrs['topo.bridge'] = p.master;

		if (p.carrier != null)
			attrs['topo.carrier'] = !!p.carrier;

		if (p.address != null)
			attrs['topo.address'] = p.address;

		if (length(p.vlans) > 0) {
			attrs['topo.vlans'] = p.vlans;
			attrs['topo.vlan_flags'] = p.flag_text;
		}

		if (p.pvid != null)
			attrs['topo.vlan_pvid'] = p.pvid;

		if (length(p.untagged) > 0)
			attrs['topo.vlan_untagged'] = p.untagged;

		push(rows, { subject: { port: p.name }, attrs });
	}

	return rows;
}

// VLAN filtering is read from the bridge's own state, never inferred from
// whether any VLAN ids happened to be seen (P4). The bridge's own link address
// comes from the generic RTM_GETLINK identity view (D47).
function bridge_rows(fs, links) {
	let rows = [], unknown = [];

	for (let name, n in links.bridges) {
		let attrs = { 'br.name': name };
		let filtering = null;
		let raw = fs.readfile(`/sys/class/net/${name}/bridge/vlan_filtering`);

		if (links.bridge_addresses?.[name] != null)
			attrs['br.address'] = links.bridge_addresses[name];

		if (raw != null && trim(raw) != '')
			filtering = (int(trim(raw)) == 1);

		if (filtering != null)
			attrs['br.vlan_filtering'] = filtering;
		else
			push(unknown, name);

		push(rows, { subject: { bridge: name }, attrs });
	}

	return { rows, unknown };
}

function fdb_rows(nl) {
	let d = dump(nl, nl.const.RTM_GETNEIGH, { family: nl.const.AF_BRIDGE });

	if (d.error)
		return { error: d.error };

	let rows = [];

	for (let e in d.rows) {
		let mac = macfmt(e.lladdr);

		if (!mac || !e.dev)
			continue;

		// A forwarding observation needs an address identity. A live
		// qualcommax/qca8k dump emitted hundreds of repeated all-zero rows on
		// DSA ports, with VIDs absent from bridge VLAN membership; the number
		// of these rows changed between consecutive dumps while every non-zero
		// MAC/port/VLAN identity remained identical. As with incomplete
		// neighbour entries below, the all-zero lladdr is therefore treated as
		// absence of a usable address identity, not as a host or FDB subject.
		if (mac == '00:00:00:00:00:00')
			continue;

		let attrs = { 'fdb.port': e.dev };

		// Omitted by the kernel when the id is zero, i.e. for untagged
		// arrivals and on non-filtering bridges. Resolving that is the
		// assembler's single permitted inference (D13), not this reader's.
		if (e.vlan != null)
			attrs['fdb.vlan'] = e.vlan;

		// Some FDB observations carry the master bridge and some do not. That
		// distinction is reported as-is; it is not portable evidence of
		// hardware/software provenance (D47).
		if (e.master != null)
			attrs['fdb.bridge'] = e.master;

		let flags = fdb_flags(nl, e.state ?? 0, e.flags ?? 0);

		if (length(flags) > 0)
			attrs['fdb.flags'] = flags;

		push(rows, { subject: { mac }, attrs });
	}

	return { rows };
}

function neigh_rows(nl) {
	let byMac = {}, errors = [];

	for (let family in [ nl.const.AF_INET, nl.const.AF_INET6 ]) {
		let d = dump(nl, nl.const.RTM_GETNEIGH, { family });

		if (d.error) {
			push(errors, d.error);
			continue;
		}

		for (let e in d.rows) {
			let mac = macfmt(e.lladdr);

			if (!mac || !e.dst)
				continue;

			// An incomplete or failed neighbour has no hardware address, and
			// the kernel reports the all-zero one. Treating that as a mapping
			// invents a host: a live switch produced
			// 00:00:00:00:00:00 -> 0.0.0.0 on the first run.
			if (mac == '00:00:00:00:00:00')
				continue;

			if ((e.state ?? 0) & (nl.const.NUD_INCOMPLETE | nl.const.NUD_FAILED))
				continue;

			byMac[mac] ??= [];

			if (!(e.dst in byMac[mac]))
				push(byMac[mac], e.dst);
		}
	}

	if (length(errors) == 2)
		return { error: errors[0] };

	let rows = [];

	for (let mac, ips in byMac)
		push(rows, { subject: { mac }, attrs: { 'neigh.ips': ips } });

	return { rows };
}

// Presence is probed per call rather than cached: a lease file only exists
// once a first lease has been issued, which can happen after this process
// started.
function name_rows(fs) {
	let byMac = {}, found = false, present = [];

	for (let path in [ '/tmp/dhcp.leases', '/var/dhcp.leases' ]) {
		if (!fs.access(path, 'r'))
			continue;

		found = true;
		push(present, path);

		for (let line in split(fs.readfile(path) ?? '', '\n')) {
			let f = split(trim(line), /[ \t]+/);

			if (length(f) < 4)
				continue;

			let mac = macfmt(f[1]);

			if (mac && f[3] != '*' && f[3] != '')
				byMac[mac] ??= f[3];
		}
	}

	if (fs.access('/etc/ethers', 'r')) {
		found = true;
		push(present, '/etc/ethers');

		for (let line in split(fs.readfile('/etc/ethers') ?? '', '\n')) {
			let f = split(trim(line), /[ \t]+/);

			if (length(f) < 2 || substr(trim(line), 0, 1) == '#')
				continue;

			let mac = macfmt(f[0]);

			if (mac)
				byMac[mac] ??= f[1];
		}
	}

	if (!found)
		return { absent: true };

	let rows = [];

	for (let mac, host in byMac)
		push(rows, { subject: { mac }, attrs: { 'name.hostname': host } });

	// `ok` with no rows is a real answer here - the files exist and map
	// nothing - but it is only legible if the reader says which files it
	// read, so the caller can tell it from having looked nowhere.
	return { rows, sources: present };
}

// -------------------------------------------------------------------- reader

return {
	id: 'rtnl',
	api: 1,
	describe: 'Kernel bridge and neighbour tables via netlink',
	provides: [ 'bridges', 'ports', 'fdb', 'neighbours', 'names' ],
	cost: 'hardware-walk',

	read: function(ctx) {
		let collections = {}, rows = [];

		if (!ctx.nl) {
			let reason = 'ucode-mod-rtnl is not available in this process';

			for (let c in this.provides)
				collections[c] = { status: 'unavailable', reason };

			return { collections, rows };
		}

		// Bridge identity needs a generic link dump; bridge-port and VLAN
		// membership need AF_BRIDGE. If either half fails, bridges and ports
		// cannot be combined without guessing, so both are declared unavailable.
		let links = read_links(ctx.nl);

		if (links.error) {
			for (let c in [ 'bridges', 'ports' ])
				collections[c] = { status: 'unavailable', reason: links.error };

			links = { ports: [], bridges: {}, bridge_addresses: {} };
		}
		else {
			let br = bridge_rows(ctx.fs, links);

			if (length(br.unknown) > 0)
				collections.bridges = {
					status: 'indeterminate',
					reason: `VLAN filtering state unreadable for: ${join(', ', br.unknown)}`
				};
			else
				collections.bridges = { status: 'ok' };

			if (collections.bridges.status == 'ok')
				rows = [ ...rows, ...br.rows ];

			collections.ports = { status: 'ok' };
			rows = [ ...rows, ...port_rows(links) ];
		}

		let fdb = fdb_rows(ctx.nl);

		if (fdb.error)
			collections.fdb = { status: 'unavailable', reason: fdb.error };
		else if (length(fdb.rows) == 0)
			// An idle switch and a driver that does not report its hardware
			// table are indistinguishable from one sample (P4).
			collections.fdb = {
				status: 'indeterminate',
				reason: 'dump succeeded with no entries; an idle bridge and a driver that does not report its table are indistinguishable from one sample'
			};
		else {
			collections.fdb = { status: 'ok' };
			rows = [ ...rows, ...fdb.rows ];
		}

		let neigh = neigh_rows(ctx.nl);

		if (neigh.error)
			collections.neighbours = { status: 'unavailable', reason: neigh.error };
		else {
			collections.neighbours = { status: 'ok' };
			rows = [ ...rows, ...neigh.rows ];
		}

		let names = name_rows(ctx.fs);

		if (names.absent)
			collections.names = {
				status: 'unavailable',
				reason: 'no lease file and no /etc/ethers on this device'
			};
		else {
			collections.names = { status: 'ok' };

			if (length(names.rows) == 0)
				collections.names.note = `read ${join(', ', names.sources)}; no address to name mappings in them`;

			rows = [ ...rows, ...names.rows ];
		}

		return { collections, rows };
	}
};