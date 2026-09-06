// SPDX-License-Identifier: Apache-2.0
//
// Synthetic snapshot for screenshots and UI demonstrations.
// This is development/demo data only; it is never installed by either package.

'use strict';

function iso8601() {
	let t = gmtime();

	return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
	               t.year, t.mon, t.mday, t.hour, t.min, t.sec);
}

return {
	format: 'l2-info.snapshot',
	version: 1,
	captured_at: iso8601(),
	duration_ms: 18,
	cost: 'software',
	device: {
		board: 'l2-info-demo',
		model: 'Synthetic l2-info demo',
		target: 'demo/synthetic',
		kernel: 'not-a-real-device'
	},
	scope: {
		readers: {
			demo: {
				status: 'ok',
				api: 1,
				cost: 'software',
				describe: 'Synthetic screenshot data',
				provides: [ 'bridges', 'ports', 'fdb', 'neighbours', 'names' ]
			}
		},
		conflicts: [],
		bridges: { status: 'ok', count: 1 },
		ports: { status: 'ok', count: 4 },
		fdb: { status: 'ok', count: 6 },
		neighbours: { status: 'ok', count: 6 },
		names: { status: 'ok', count: 5 }
	},
	bridges: [
		{
			subject: { bridge: 'br-lan' },
			attrs: {
				'br.name': 'br-lan',
				'br.address': '02:00:00:ff:ff:01',
				'br.vlan_filtering': true
			},
			derived: { port_count: 4 },
			source: 'demo'
		}
	],
	ports: [
		{
			subject: { port: 'lan1' },
			attrs: {
				'topo.port': 'lan1', 'topo.bridge': 'br-lan', 'topo.carrier': true,
				'topo.vlans': [ 10 ], 'topo.vlan_flags': [ 'PVID Egress Untagged' ],
				'topo.vlan_pvid': 10, 'topo.vlan_untagged': [ 10 ]
			},
			derived: { mac_count: 2, vlans_observed: [ 10 ] }, source: 'demo'
		},
		{
			subject: { port: 'lan2' },
			attrs: {
				'topo.port': 'lan2', 'topo.bridge': 'br-lan', 'topo.carrier': true,
				'topo.vlans': [ 20 ], 'topo.vlan_flags': [ 'PVID Egress Untagged' ],
				'topo.vlan_pvid': 20, 'topo.vlan_untagged': [ 20 ]
			},
			derived: { mac_count: 1, vlans_observed: [ 20 ] }, source: 'demo'
		},
		{
			subject: { port: 'lan3' },
			attrs: {
				'topo.port': 'lan3', 'topo.bridge': 'br-lan', 'topo.carrier': true,
				'topo.vlans': [ 30 ], 'topo.vlan_flags': [ 'PVID Egress Untagged' ],
				'topo.vlan_pvid': 30, 'topo.vlan_untagged': [ 30 ]
			},
			derived: { mac_count: 1, vlans_observed: [ 30 ] }, source: 'demo'
		},
		{
			subject: { port: 'lan4' },
			attrs: {
				'topo.port': 'lan4', 'topo.bridge': 'br-lan', 'topo.carrier': true,
				'topo.vlans': [ 10, 20, 30 ], 'topo.vlan_flags': [ '', '', '' ],
				'topo.vlan_untagged': []
			},
			derived: { mac_count: 2, vlans_observed: [ 20, 30 ] }, source: 'demo'
		}
	],
	fdb: [
		{
			subject: { mac: '02:00:00:00:10:01' },
			attrs: { 'fdb.port': 'lan1', 'fdb.vlan': 10, 'fdb.bridge': 'br-lan' },
			derived: { bridge: 'br-lan', mac_class: 'unicast', vlan: 10, vlan_source: 'fdb', on_bridge_device: false, local: false, ips: [ '192.0.2.11' ], hostname: 'demo-laptop' },
			source: 'demo'
		},
		{
			subject: { mac: '02:00:00:00:10:02' },
			attrs: { 'fdb.port': 'lan1', 'fdb.bridge': 'br-lan' },
			derived: { bridge: 'br-lan', mac_class: 'unicast', vlan: 10, vlan_source: 'pvid', on_bridge_device: false, local: false, ips: [ '192.0.2.12' ], hostname: 'demo-tablet' },
			source: 'demo'
		},
		{
			subject: { mac: '02:00:00:00:20:01' },
			attrs: { 'fdb.port': 'lan2', 'fdb.vlan': 20, 'fdb.bridge': 'br-lan' },
			derived: { bridge: 'br-lan', mac_class: 'unicast', vlan: 20, vlan_source: 'fdb', on_bridge_device: false, local: false, ips: [ '192.0.2.21' ], hostname: 'demo-printer' },
			source: 'demo'
		},
		{
			subject: { mac: '02:00:00:00:30:01' },
			attrs: { 'fdb.port': 'lan3', 'fdb.vlan': 30, 'fdb.bridge': 'br-lan' },
			derived: { bridge: 'br-lan', mac_class: 'unicast', vlan: 30, vlan_source: 'fdb', on_bridge_device: false, local: false, ips: [ '192.0.2.31' ] },
			source: 'demo'
		},
		{
			subject: { mac: '02:00:00:00:40:01' },
			attrs: { 'fdb.port': 'lan4', 'fdb.vlan': 20, 'fdb.bridge': 'br-lan' },
			derived: { bridge: 'br-lan', mac_class: 'unicast', vlan: 20, vlan_source: 'fdb', on_bridge_device: false, local: false, ips: [ '192.0.2.41' ], hostname: 'demo-phone' },
			source: 'demo'
		},
		{
			subject: { mac: '02:00:00:00:40:02' },
			attrs: { 'fdb.port': 'lan4', 'fdb.vlan': 30, 'fdb.bridge': 'br-lan' },
			derived: { bridge: 'br-lan', mac_class: 'unicast', vlan: 30, vlan_source: 'fdb', on_bridge_device: false, local: false, ips: [ '192.0.2.42' ], hostname: 'demo-pc' },
			source: 'demo'
		}
	],
	neighbours: [
		{ subject: { mac: '02:00:00:00:10:01' }, attrs: { 'neigh.ips': [ '192.0.2.11' ] }, source: 'demo' },
		{ subject: { mac: '02:00:00:00:10:02' }, attrs: { 'neigh.ips': [ '192.0.2.12' ] }, source: 'demo' },
		{ subject: { mac: '02:00:00:00:20:01' }, attrs: { 'neigh.ips': [ '192.0.2.21' ] }, source: 'demo' },
		{ subject: { mac: '02:00:00:00:30:01' }, attrs: { 'neigh.ips': [ '192.0.2.31' ] }, source: 'demo' },
		{ subject: { mac: '02:00:00:00:40:01' }, attrs: { 'neigh.ips': [ '192.0.2.41' ] }, source: 'demo' },
		{ subject: { mac: '02:00:00:00:40:02' }, attrs: { 'neigh.ips': [ '192.0.2.42' ] }, source: 'demo' }
	],
	names: [
		{ subject: { mac: '02:00:00:00:10:01' }, attrs: { 'name.hostname': 'demo-laptop' }, source: 'demo' },
		{ subject: { mac: '02:00:00:00:10:02' }, attrs: { 'name.hostname': 'demo-tablet' }, source: 'demo' },
		{ subject: { mac: '02:00:00:00:20:01' }, attrs: { 'name.hostname': 'demo-printer' }, source: 'demo' },
		{ subject: { mac: '02:00:00:00:40:01' }, attrs: { 'name.hostname': 'demo-phone' }, source: 'demo' },
		{ subject: { mac: '02:00:00:00:40:02' }, attrs: { 'name.hostname': 'demo-pc' }, source: 'demo' }
	]
};
