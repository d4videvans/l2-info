// Manifest id does not match the filename, so it could shadow another reader
// or misattribute provenance.
return {
	id: 'something-else',
	api: 1,
	describe: 'Reader whose id does not match its filename',
	provides: [ 'ports' ],
	cost: 'software',
	read: () => ({ collections: { ports: { status: 'ok' } }, rows: [] })
};
