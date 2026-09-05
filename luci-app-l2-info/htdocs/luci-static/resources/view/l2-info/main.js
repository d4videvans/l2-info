/* SPDX-License-Identifier: Apache-2.0 */
/* l2-info - locate MAC addresses across this device's ports and VLANs.
 *
 * Takes one snapshot when asked, then answers every question from it without
 * reading the hardware again (D2). Keeps the current and the previous
 * snapshot in memory only, and nothing on disk (D10, D11).
 */

'use strict';
'require view';
'require rpc';
'require ui';
'require dom';
'require l2-info.hints as hints';
'require l2-info.query as query';
'require l2-info.diff as compare';

var callSnapshot = rpc.declare({
	object: 'l2-info',
	method: 'snapshot',
	expect: { }
});

var S = {
	current: null,
	currentAt: null,
	previous: null,
	query: { port: '', vlan: '', mac: '', nonUnicast: false }
};

function el(tag, attrs, children) {
	return E(tag, attrs || {}, children);
}

function table(headings, rows, placeholder) {
	var t = el('table', { 'class': 'table cbi-section-table' }, [
		el('tr', { 'class': 'tr cbi-section-table-titles' }, headings.map(function(h) {
			return el('th', { 'class': 'th' }, h);
		}))
	]);

	cbi_update_table(t, rows, el('em', {}, placeholder));

	return t;
}

/* ------------------------------------------------------------------ export */

/* Reported facts and declared scope, with derivation and interpretation
 * removed: the file says what was read, not what was made of it (P3, P5). */
/* Built from a declared list of registered keys rather than by deleting what
 * should not be there. A first version copied the snapshot and deleted
 * `derived`, which let the view's own receive timestamp into the file: a
 * denylist only removes what it already knows about, which is the same lesson
 * the fixture redaction learned the hard way (D45, D15). */
var EXPORT_KEYS = [
	'format', 'version', 'captured_at', 'duration_ms', 'cost', 'device', 'scope'
];

var EXPORT_COLLECTIONS = [ 'bridges', 'ports', 'fdb', 'neighbours', 'names' ];

function exportable(snap) {
	var out = {};

	EXPORT_KEYS.forEach(function(k) {
		if (snap[k] !== undefined)
			out[k] = JSON.parse(JSON.stringify(snap[k]));
	});

	EXPORT_COLLECTIONS.forEach(function(c) {
		out[c] = (snap[c] || []).map(function(e) {
			var row = { subject: e.subject, attrs: e.attrs, source: e.source };

			if (e.disputed)
				row.disputed = e.disputed;

			return JSON.parse(JSON.stringify(row));
		});
	});

	return out;
}

function download(snap) {
	var name = 'l2-info-%s-%s.json'.format(
		(snap.device.board || 'device').replace(/[^A-Za-z0-9._-]/g, '_'),
		(snap.captured_at || '').replace(/[:]/g, ''));

	var blob = new Blob([ JSON.stringify(exportable(snap), null, 2) ],
	                    { type: 'application/json' });
	var url = URL.createObjectURL(blob);
	var a = el('a', { 'href': url, 'download': name });

	document.body.appendChild(a);
	a.click();
	document.body.removeChild(a);
	URL.revokeObjectURL(url);
}

/* ---------------------------------------------------------------- renderers */

function fmtVlan(d) {
	if (d.vlan == null)
		return el('em', {}, _('none'));

	if (d.vlan_source == 'pvid')
		return el('span', {
			'title': _('Untagged arrival: this is the port\'s native VLAN, not a value from the forwarding entry.')
		}, [ String(d.vlan), ' ', el('em', {}, _('(native)')) ]);

	return String(d.vlan);
}

function fmtIdentity(d) {
	if (d.hostname)
		return d.hostname;

	if (d.ips && d.ips.length)
		return d.ips.join(', ');

	/* Reported, not guessed: the address matches one this device's own ports
	 * carry. Saying so is what stops it reading as a host that is everywhere. */
	if (d.local)
		return el('em', { 'title': _('This address belongs to this device.') },
			_('this device'));

	return el('em', {}, _('unknown'));
}

function fmtDisputed(e) {
	if (!e.disputed)
		return null;

	return Object.keys(e.disputed).map(function(a) {
		return el('div', { 'class': 'alert-message warning' }, [
			_('%s is disputed:').format(a), ' ',
			e.disputed[a].map(function(c) {
				return '%s says %s'.format(c.source, JSON.stringify(c.value));
			}).join('; ')
		]);
	});
}

function fmtStatus(status) {
	if (status == 'ok')
		return _('available');
	if (status == 'unavailable')
		return _('unavailable');
	if (status == 'not_applicable')
		return _('not applicable');
	if (status == 'indeterminate')
		return _('indeterminate');
	if (status == 'skipped')
		return _('skipped');

	return status || _('unreported');
}

function fmtCollection(name) {
	var labels = {
		bridges: _('Bridges'),
		ports: _('Ports'),
		fdb: _('Forwarding database'),
		neighbours: _('Neighbours'),
		names: _('Names')
	};

	return labels[name] || name;
}

function fmtScopeStatus(st) {
	var parts = [ fmtStatus(st.status) ];

	if (st.reason)
		parts.push(st.reason);
	if (st.note)
		parts.push(st.note);

	return parts.join(' — ');
}

function coverageProblems(snap) {
	return [ 'bridges', 'ports', 'fdb', 'neighbours', 'names' ].filter(function(c) {
		var st = snap.scope[c] || {};
		return st.status != 'ok' && st.status != 'not_applicable';
	});
}

function renderSnapshotSummary(snap) {
	var d = snap.device || {};
	var fdbScope = snap.scope.fdb || {};
	var problems = coverageProblems(snap);
	var conflicts = (snap.scope.conflicts || []).length;
	var coverage = problems.length
		? el('span', { 'class': 'label warning' },
			_('%d data areas need attention').format(problems.length))
		: el('span', { 'class': 'label success' }, _('All requested data available'));
	var raw = (fdbScope.count != null) ? fdbScope.count : (snap.fdb || []).length;

	var rows = [
		[ _('Device'), d.model || d.board || _('unreported') ],
		[ _('Topology'), _('%d bridges, %d ports').format((snap.bridges || []).length, (snap.ports || []).length) ],
		[ _('Forwarding entries'), _('%d assembled, %d raw').format((snap.fdb || []).length, raw) ],
		[ _('Neighbours'), String((snap.neighbours || []).length) ],
		[ _('Read time'), _('%d ms').format(snap.duration_ms || 0) ],
		[ _('Coverage'), coverage ]
	];

	if (conflicts)
		rows.push([ _('Conflicts'), el('span', { 'class': 'label warning' }, String(conflicts)) ]);

	return table([ _('Snapshot summary'), _('Value') ], rows, _('Nothing reported.'));
}

function renderQueryErrors(errors) {
	if (!errors.length)
		return el('div', {});

	var messages = [];

	if (errors.indexOf('vlan-format') >= 0 || errors.indexOf('vlan-range') >= 0)
		messages.push(_('VLAN must be a whole number from 1 to 4094.'));

	if (errors.indexOf('mac-format') >= 0)
		messages.push(_('MAC search contains characters that are not hexadecimal or standard separators.'));

	if (errors.indexOf('mac-length') >= 0)
		messages.push(_('MAC search is longer than a 48-bit MAC address.'));

	return el('div', { 'class': 'alert-message warning' }, messages.join(' '));
}

function renderHints(list) {
	if (!list.length)
		return el('div', {});

	return el('div', {}, list.map(function(h) {
		return el('div', {
			'class': 'cbi-value-description',
			'data-hint': h.id
		}, [ (h.kind == 'likely') ? el('strong', {}, _('Likely: ')) : '', h.text ]);
	}));
}

function renderResults(snap, rows) {
	var body = rows.map(function(r) {
		return [
			el('code', {}, r.subject.mac),
			r.attrs['fdb.port'] || '?',
			r.derived.bridge || el('em', {}, '–'),
			fmtVlan(r.derived),
			(r.attrs['fdb.flags'] || []).join(' ') || el('em', {}, '–'),
			fmtIdentity(r.derived)
		];
	});

	var hidden = (snap.fdb || []).length - (snap.fdb || []).filter(function(r) {
		return r.derived.mac_class == 'unicast';
	}).length;

	var note = [ _('%d of %d forwarding entries shown.').format(rows.length, (snap.fdb || []).length) ];

	if (hidden && !S.query.nonUnicast)
		note.push(_('%d multicast or protocol addresses are hidden.').format(hidden));

	return el('div', {}, [
		table([ _('MAC'), _('Port'), _('Bridge'), _('VLAN'), _('Flags'), _('Host / IP') ],
		      body, _('No matching entries.')),
		el('div', { 'class': 'cbi-value-description' }, note.join(' '))
	]);
}

function renderPorts(snap) {
	var body = (snap.ports || []).map(function(p) {
		var vlans = p.attrs['topo.vlans'] || [];
		var pvid = p.attrs['topo.vlan_pvid'];
		var untagged = p.attrs['topo.vlan_untagged'] || [];

		return [
			p.subject.port,
			p.attrs['topo.bridge'] || el('em', {}, '–'),
			(p.attrs['topo.carrier'] === true) ? _('up')
				: (p.attrs['topo.carrier'] === false) ? _('down') : el('em', {}, '–'),
			vlans.length ? vlans.map(function(v) {
				return String(v) + (v == pvid ? '*' : '') + (untagged.indexOf(v) >= 0 ? 'u' : 't');
			}).join(' ') : el('em', {}, '–'),
			String(p.derived.mac_count),
			(p.derived.vlans_observed || []).join(' ') || el('em', {}, '–')
		];
	});

	return el('div', {}, [
		table([ _('Port'), _('Bridge'), _('Link'), _('VLANs'), _('Addresses'), _('VLANs seen') ],
		      body, _('No ports reported.')),
		el('div', { 'class': 'cbi-value-description' },
			_('u = untagged, t = tagged, * = native VLAN. Read from the kernel, not from configuration.')),
		el('div', {}, (snap.ports || []).map(fmtDisputed).filter(Boolean))
	]);
}

/* What this device is, and what it could and could not see. Evidence, with
 * conclusions only where they follow from it (P4). */
function renderScope(snap) {
	var d = snap.device || {};

	var rows = [
		[ _('Model'), d.model || d.board || el('em', {}, _('unreported')) ],
		[ _('Target'), d.target || el('em', {}, _('unreported')) ],
		[ _('Kernel'), d.kernel || el('em', {}, _('unreported')) ]
	];

	(snap.bridges || []).forEach(function(b) {
		var f = b.attrs['br.vlan_filtering'];

		rows.push([
			_('Bridge %s').format(b.subject.bridge),
			(f === true) ? _('VLAN filtering on, %d ports').format(b.derived.port_count)
				: (f === false) ? _('VLAN filtering off, %d ports').format(b.derived.port_count)
				: _('VLAN filtering state unreadable, %d ports').format(b.derived.port_count)
		]);
	});

	[ 'bridges', 'ports', 'fdb', 'neighbours', 'names' ].forEach(function(c) {
		var st = snap.scope[c] || {};

		rows.push([ fmtCollection(c), fmtScopeStatus(st) ]);
	});

	Object.keys(snap.scope.readers || {}).forEach(function(id) {
		var r = snap.scope.readers[id];

		rows.push([
			_('Reader %s').format(id),
			fmtScopeStatus(r) + (r.describe ? ' (' + r.describe + ')' : '')
		]);
	});

	return table([ _('Property'), _('Value') ], rows, _('Nothing reported.'));
}

function fmtScopeDifference(d) {
	if (d.kind == 'format-version')
		return _('snapshot format/version');

	if (d.kind == 'collection-status')
		return _('%s status (%s → %s)').format(fmtCollection(d.collection), fmtStatus(d.before), fmtStatus(d.after));

	if (d.kind == 'collection-coverage')
		return _('%s coverage details').format(fmtCollection(d.collection));

	if (d.kind == 'reader-coverage')
		return _('reader coverage');

	return _('unknown scope difference');
}

function renderDiff() {
	if (!S.previous)
		return el('div', {}, el('em', {},
			_('Take another snapshot to compare changes.')));

	var differ = compare.scopeCompatible(S.current, S.previous);

	if (differ.length)
		return el('div', { 'class': 'alert-message warning' },
			_('These two snapshots read different things, so they cannot be compared: %s.')
				.format(differ.map(fmtScopeDifference).join(', ')));

	var d = compare.diff(S.current, S.previous);

	var rows = d.moved.map(function(m) {
		return [
			el('code', {}, m.mac),
			_('moved'),
			'%s → %s'.format(m.from, m.to),
			m.weak ? el('em', {}, _('VLAN partly inferred')) : ''
		];
	}).concat(d.appeared.filter(function(r) {
		return !d.moved.some(function(m) { return m.mac == r.subject.mac; });
	}).map(function(r) {
		return [ el('code', {}, r.subject.mac), _('appeared'), r.attrs['fdb.port'], '' ];
	})).concat(d.vanished.filter(function(r) {
		return !d.moved.some(function(m) { return m.mac == r.subject.mac; });
	}).map(function(r) {
		return [ el('code', {}, r.subject.mac), _('gone'), r.attrs['fdb.port'], '' ];
	}));

	return el('div', {}, [
		table([ _('MAC'), _('Change'), _('Port'), _('Note') ], rows, _('Nothing changed.')),
		el('div', { 'class': 'cbi-value-description' },
			_('Comparing %s with %s. "Moved" is inferred only when one remote unicast address leaves exactly one port and appears on exactly one other port.')
				.format(S.previous.captured_at, S.current.captured_at))
	]);
}

/* ------------------------------------------------------------------- view */

return view.extend({
	load: function() {
		return Promise.resolve();
	},

	render: function() {
		var self = this;

		var age = el('span', {}, _('not taken'));
		var summaryBox = el('div', {}, el('em', {}, _('Take a snapshot to begin.')));
		var resultsBox = el('div', {});
		var portsBox = el('div', {});
		var scopeBox = el('div', {});
		var diffBox = el('div', {});
		var hintsBox = el('div', {});
		var queryNotice = el('div', {});
		var contentBox;
		var detailsBox;

		var inPort = el('select', { 'class': 'cbi-input-select' },
			el('option', { 'value': '' }, _('any port')));
		var inVlan = el('input', { 'type': 'number', 'class': 'cbi-input-text',
			'min': '1', 'max': '4094', 'step': '1',
			'style': 'width:7em', 'placeholder': _('any') });
		var inMac = el('input', { 'type': 'text', 'class': 'cbi-input-text',
			'style': 'width:20em', 'placeholder': _('full or partial') });
		var inAll = el('input', { 'type': 'checkbox' });

		/* Ages the label only. There is no data poll anywhere: the snapshot
		 * changes when the user presses Update and at no other time, and P6
		 * requires that its age be visible while it sits there. */
		function updateAge() {
			if (!S.current) {
				dom.content(age, _('not taken'));
				return;
			}

			var secs = Math.max(0, Math.round((Date.now() - S.currentAt) / 1000));
			var when = (secs < 60) ? _('%d s ago').format(secs)
				: (secs < 3600) ? _('%d min ago').format(Math.round(secs / 60))
				: _('%d h ago').format(Math.round(secs / 3600));

			dom.content(age, [ S.current.captured_at, ' (', when, ')' ]);
		}

		function tick() {
			updateAge();

			/* One timeout may fire after navigation; it sees the detached age
			 * node and stops. No interval survives a discarded view. */
			if (age.isConnected)
				window.setTimeout(tick, 1000);
		}

		/* render() returns before the node is attached, so start one tick
		 * later; subsequent scheduling is conditional on DOM attachment. */
		window.setTimeout(tick, 1000);

		function readQuery() {
			S.query = {
				port: inPort.value,
				vlan: inVlan.value,
				mac: inMac.value,
				nonUnicast: inAll.checked
			};
		}

		function redrawQuery() {
			if (!S.current)
				return;

			readQuery();

			var filtered = query.filterRows(S.current, S.query);
			var rows = filtered.rows;

			dom.content(queryNotice, renderQueryErrors(filtered.query.errors));
			dom.content(resultsBox, renderResults(S.current, rows));
			dom.content(hintsBox, renderHints(hints.evaluate(S.current, {
				rows: rows, port: S.query.port
			})));
		}

		function resetQuery() {
			inPort.value = '';
			inVlan.value = '';
			inMac.value = '';
			inAll.checked = false;
			redrawQuery();
		}

		function redrawAll() {
			var snap = S.current;

			dom.content(summaryBox, renderSnapshotSummary(snap));
			dom.content(portsBox, renderPorts(snap));
			dom.content(scopeBox, renderScope(snap));
			dom.content(diffBox, renderDiff());
			contentBox.style.display = '';
			detailsBox.open = coverageProblems(snap).length > 0 || (snap.scope.conflicts || []).length > 0;

			/* Forwarding entries can name interfaces that are not bridge
			 * ports and so have no port row — a conduit interface and its
			 * VLAN sub-interfaces, for instance. Building the list from the
			 * ports collection alone would leave those rows unreachable by
			 * the port filter. */
			var seen = {}, names = [];

			(snap.ports || []).forEach(function(p) {
				if (!seen[p.subject.port]) {
					seen[p.subject.port] = true;
					names.push(p.subject.port);
				}
			});

			(snap.fdb || []).forEach(function(r) {
				var n = r.attrs['fdb.port'];

				if (n && !seen[n]) {
					seen[n] = true;
					names.push(n);
				}
			});

			var opts = [ el('option', { 'value': '' }, _('any port')) ].concat(
				names.map(function(n) {
					return el('option', { 'value': n }, n);
				}));

			var keep = inPort.value;

			dom.content(inPort, opts);
			inPort.value = keep;

			redrawQuery();
			updateAge();
		}

		function update(ev) {
			var btn = ev.target;

			btn.classList.add('spinning');
			btn.disabled = true;

			return callSnapshot().then(function(snap) {
				if (!snap || !snap.scope) {
					ui.addNotification(null, el('p', {},
						_('The backend returned nothing usable. Is the l2-info package installed?')));
					return;
				}

				S.previous = S.current;
				S.current = snap;
				S.currentAt = Date.now();

				redrawAll();
			}).catch(function(e) {
				ui.addNotification(null, el('p', {},
					_('Reading the snapshot failed: %s').format(e.message)));
			}).finally(function() {
				btn.classList.remove('spinning');
				btn.disabled = false;
			});
		}

		[ inVlan, inMac ].forEach(function(i) {
			i.addEventListener('input', redrawQuery);
		});

		[ inPort, inAll ].forEach(function(i) {
			i.addEventListener('change', redrawQuery);
		});

		function field(label, input) {
			return el('div', { 'class': 'cbi-value' }, [
				el('label', { 'class': 'cbi-value-title' }, label),
				el('div', { 'class': 'cbi-value-field' }, input)
			]);
		}

		detailsBox = el('details', { 'class': 'cbi-section' }, [
			el('summary', {}, el('strong', {}, _('Device and data-source details'))),
			el('div', { 'style': 'margin-top:1em' }, scopeBox)
		]);

		contentBox = el('div', { 'style': 'display:none' }, [
			el('div', { 'class': 'cbi-section' }, [
				el('h3', {}, _('Filter snapshot')),
				el('div', { 'class': 'cbi-section-descr' },
					_('These filters use the current snapshot and do not read the hardware again.')),
				field(_('Port'), inPort),
				field(_('VLAN'), inVlan),
				field(_('MAC'), inMac),
				field(_('Include multicast and protocol addresses'), inAll),
				el('div', { 'class': 'cbi-value' }, [
					el('div', { 'class': 'cbi-value-title' }),
					el('div', { 'class': 'cbi-value-field' },
						el('button', { 'class': 'cbi-button', 'click': resetQuery }, _('Reset filters')))
				]),
				queryNotice
			]),

			el('div', { 'class': 'cbi-section' }, [
				el('h3', {}, _('Matching addresses')),
				resultsBox,
				hintsBox
			]),

			el('div', { 'class': 'cbi-section' }, [
				el('h3', {}, _('Ports and VLANs')),
				portsBox
			]),

			el('div', { 'class': 'cbi-section' }, [
				el('h3', {}, _('Changes since the previous snapshot')),
				diffBox
			]),

			detailsBox
		]);

		return el('div', {}, [
			el('h2', {}, _('MAC & VLAN Lookup')),
			el('div', { 'class': 'cbi-map-descr' },
				_('Take one read-only snapshot of this device\'s live Layer 2 state, then filter and compare it without polling the hardware. Nothing is stored.')),

			el('div', { 'class': 'cbi-section' }, [
				el('h3', {}, _('Snapshot')),
				el('div', { 'class': 'cbi-value' }, [
					el('label', { 'class': 'cbi-value-title' }, _('Actions')),
					el('div', { 'class': 'cbi-value-field' }, [
						el('button', {
							'class': 'cbi-button cbi-button-action important',
							'click': ui.createHandlerFn(self, update)
						}, _('Update snapshot')),
						' ',
						el('button', {
							'class': 'cbi-button',
							'click': function() {
								if (S.current)
									download(S.current);
								else
									ui.addNotification(null, el('p', {}, _('Take a snapshot first.')));
							}
						}, _('Download JSON'))
					])
				]),
				el('div', { 'class': 'cbi-value' }, [
					el('label', { 'class': 'cbi-value-title' }, _('Last snapshot')),
					el('div', { 'class': 'cbi-value-field' }, age)
				]),
				summaryBox
			]),

			contentBox
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
