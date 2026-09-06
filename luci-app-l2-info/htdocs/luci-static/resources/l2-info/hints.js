/* SPDX-License-Identifier: Apache-2.0 */
/* l2-info hints - interpretation, which lives in presentation and never in
 * the data (P5).
 *
 * Every hint here obeys four rules:
 *
 *   H1  it is never a field. Delete this file and the app is still correct and
 *       complete; it only becomes terser.
 *   H2  it uses only values the page displays, so a reader can check the
 *       reasoning against the numbers beside it.
 *   H3  a hint of kind 'likely' names at least two plausible causes. If a
 *       second cause cannot be named, it is a verdict wearing a hedge and does
 *       not ship. Kind 'note' explains what is on screen and asserts nothing
 *       about the world, so the two-cause rule does not apply to it.
 *   H4  it is a pure function of its inputs, so its firing is testable.
 *
 * Kept in its own module so it can be unit tested outside a browser: hints are
 * asserted by tests/hints.test.js against the same device fixtures the
 * assembler is tested with.
 */

'use strict';
'require baseclass';

return baseclass.extend({
	/* Each rule: id, kind, and a function returning null or a hint.
	 * `view` carries what the page is currently showing, so a hint cannot
	 * reason about anything the user cannot see (H2). */
	rules: [
		{
			id: 'fdb_indeterminate',
			kind: 'note',
			test: function(s) {
				if (s.scope.fdb?.status != 'indeterminate')
					return null;

				return _('No forwarding entries were reported. An idle bridge and a switch driver that does not report its hardware table look identical from a single read, so this is recorded as undetermined rather than empty.');
			}
		},
		{
			id: 'fdb_unavailable',
			kind: 'note',
			test: function(s) {
				if (s.scope.fdb?.status != 'unavailable')
					return null;

				return _('The forwarding database could not be read: %s').format(s.scope.fdb.reason ?? '');
			}
		},
		{
			id: 'no_reader',
			kind: 'note',
			test: function(s, view) {
				var unclaimed = Object.keys(s.scope).filter(function(k) {
					return s.scope[k] && s.scope[k].status == 'not_applicable';
				});

				if (!unclaimed.length)
					return null;

				var label = view.collectionLabel || function(name) { return name; };

				return _('Nothing installed on this device can read: %s. Installing a reader package adds that capability.').format(unclaimed.map(label).join(', '));
			}
		},
		{
			id: 'no_vlan_filtering',
			kind: 'note',
			test: function(s) {
				var off = (s.bridges || []).filter(function(b) {
					return b.attrs['br.vlan_filtering'] === false;
				});

				if (!off.length || off.length != (s.bridges || []).length)
					return null;

				return _('No bridge on this device has VLAN filtering enabled. Bridge VLAN filtering is therefore not providing VLAN separation here. Values marked native come from the port PVID rather than a VLAN reported by the forwarding entry; 802.1Q tagging may still be handled at the interface layer, for example with VLAN interfaces and separate bridges.');
			}
		},
		{
			id: 'pvid_inferred',
			kind: 'note',
			test: function(s, view) {
				var n = (view.rows || []).filter(function(r) {
					return r.derived.vlan_source == 'pvid';
				}).length;

				if (!n)
					return null;

				return _('%d of the addresses shown arrived untagged. The forwarding database records no VLAN for those, so the VLAN column shows the port\'s own native VLAN and is marked accordingly.').format(n);
			}
		},
		{
			id: 'port_multiple_macs',
			kind: 'likely',
			test: function(s, view) {
				if (!view.port)
					return null;

				var p = (s.ports || []).filter(function(x) {
					return x.subject.port == view.port;
				})[0];

				if (!p || (p.derived.mac_count ?? 0) < 2)
					return null;

				return _('%s has %d addresses behind it. That is usually an unmanaged switch or hub, but a hypervisor bridging guest machines or a desk phone with a PC passthrough port looks the same from here.').format(view.port, p.derived.mac_count);
			}
		},
		{
			id: 'trunk_shape',
			kind: 'likely',
			test: function(s, view) {
				if (!view.port)
					return null;

				var p = (s.ports || []).filter(function(x) {
					return x.subject.port == view.port;
				})[0];

				if (!p)
					return null;

				var vlans = p.attrs['topo.vlans'] || [];

				if (vlans.length < 3 || p.attrs['topo.vlan_pvid'] != null)
					return null;

				return _('%s carries %d VLANs and has no native VLAN, so everything on it is tagged. That shape is typical of a link to another managed switch, or of a single tagged link to a router.').format(view.port, vlans.length);
			}
		},
		{
			id: 'mac_on_several_ports',
			kind: 'likely',
			test: function(s, view) {
				var ports = {};

				(view.rows || []).forEach(function(r) {
					var m = r.subject.mac, p = r.attrs['fdb.port'];

					if (!m || !p)
						return;

					/* The device's own address is installed on every port and
					 * every VLAN, so it is on many ports for a reason none of
					 * the causes below describes. */
					if (r.derived.local)
						return;

					ports[m] = ports[m] || {};
					ports[m][p] = true;
				});

				var many = Object.keys(ports).filter(function(m) {
					return Object.keys(ports[m]).length > 1;
				});

				if (!many.length)
					return null;

				return _('%d address(es) appear on more than one port: %s. A client that has just moved, a link aggregation, or a bridging loop all produce this.').format(many.length, many.slice(0, 3).join(', '));
			}
		},
		{
			id: 'duplicate_reports',
			kind: 'note',
			test: function(s, view) {
				var seen = {}, dup = 0;

				(view.rows || []).forEach(function(r) {
					if (r.derived.local)
						return;

					var effective = (r.derived.vlan == null) ? 'none' : String(r.derived.vlan);
					var reported = (r.attrs['fdb.vlan'] === undefined) ? 'none' : String(r.attrs['fdb.vlan']);
					var k = r.subject.mac + '/' + r.attrs['fdb.port'] + '/' + effective;

					if (seen[k] !== undefined && seen[k] != reported)
						dup++;
					else if (seen[k] === undefined)
						seen[k] = reported;
				});

				if (!dup)
					return null;

				return _('%d address observation(s) are listed more than once on the same port with different forwarding-table details. They are kept separate because l2-info does not use an inferred native VLAN to decide that two kernel observations are the same entry.').format(dup);
			}
		},
		{
			id: 'conflict',
			kind: 'note',
			test: function(s) {
				var c = s.scope.conflicts || [];

				if (!c.length)
					return null;

				return _('%d value(s) are reported differently by different readers and are shown as disputed rather than resolved. Nothing here picks a winner.').format(c.length);
			}
		},
		{
			id: 'names_unavailable',
			kind: 'note',
			test: function(s) {
				if (s.scope.names?.status != 'unavailable')
					return null;

				return _('Host names are blank because this device has no DHCP leases and no /etc/ethers. That is normal on a switch; the names live wherever DHCP runs.');
			}
		}
	],

	/* Pure: snapshot plus what the page is showing, in; hints out. */
	evaluate: function(snapshot, view) {
		var out = [];

		if (!snapshot || !snapshot.scope)
			return out;

		view = view || {};

		this.rules.forEach(function(rule) {
			var text = rule.test(snapshot, view);

			if (text)
				out.push({ id: rule.id, kind: rule.kind, text: text });
		});

		return out;
	}
});
