// A minimal valid reader.
return {
	id: 'good',
	api: 1,
	describe: 'Valid reader for discovery tests',
	provides: [ 'ports' ],
	cost: 'software',
	read: () => ({ collections: { ports: { status: 'ok' } }, rows: [] })
};
