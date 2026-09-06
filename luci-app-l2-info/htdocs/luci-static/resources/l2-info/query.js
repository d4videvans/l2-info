/* SPDX-License-Identifier: Apache-2.0 */
/* Pure query parsing and filtering for l2-info. */

'use strict';
'require baseclass';

function parseVlan(value) {
	var raw = String(value ?? '').trim();

	if (raw === '')
		return { value: null, error: null };

	if (!/^[0-9]+$/.test(raw))
		return { value: null, error: 'vlan-format' };

	var vlan = Number(raw);

	if (vlan < 1 || vlan > 4094)
		return { value: null, error: 'vlan-range' };

	return { value: vlan, error: null };
}

function parseMac(value) {
	var raw = String(value ?? '').trim().toLowerCase();

	if (raw === '')
		return { value: '', error: null };

	/* Permit common MAC punctuation while keeping every other character
	 * significant. The previous "strip anything non-hex" behaviour made an
	 * input such as "zz" become an empty query and silently match everything. */
	var compact = raw.replace(/[:.\-\s]/g, '');

	if (compact === '' || /[^0-9a-f]/.test(compact))
		return { value: '', error: 'mac-format' };

	if (compact.length > 12)
		return { value: '', error: 'mac-length' };

	return { value: compact, error: null };
}

function parseQuery(q) {
	var vlan = parseVlan(q?.vlan);
	var mac = parseMac(q?.mac);
	var errors = [];

	if (vlan.error)
		errors.push(vlan.error);
	if (mac.error)
		errors.push(mac.error);

	return {
		port: q?.port || '',
		vlan: vlan.value,
		mac: mac.value,
		nonUnicast: !!q?.nonUnicast,
		errors: errors
	};
}

function compactMac(value) {
	return String(value || '').toLowerCase().replace(/[^0-9a-f]/g, '');
}

function filterRows(snap, q) {
	var parsed = parseQuery(q);

	if (parsed.errors.length)
		return { rows: [], populationCount: 0, hiddenNonUnicast: 0, query: parsed };

	var population = (snap.fdb || []).filter(function(r) {
		if (parsed.port && r.attrs['fdb.port'] != parsed.port)
			return false;

		if (parsed.vlan !== null && r.derived.vlan !== parsed.vlan)
			return false;

		if (parsed.mac && compactMac(r.subject.mac).indexOf(parsed.mac) < 0)
			return false;

		return true;
	});

	var hidden = population.filter(function(r) {
		return r.derived.mac_class != 'unicast';
	}).length;
	var rows = parsed.nonUnicast ? population : population.filter(function(r) {
		return r.derived.mac_class == 'unicast';
	});

	return {
		rows: rows,
		populationCount: population.length,
		hiddenNonUnicast: parsed.nonUnicast ? 0 : hidden,
		query: parsed
	};
}

return baseclass.extend({
	parseVlan: parseVlan,
	parseMac: parseMac,
	parseQuery: parseQuery,
	filterRows: filterRows
});
