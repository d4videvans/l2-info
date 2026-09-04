// Declares an interface version this core does not support.
return {
	id: 'future-api',
	api: 2,
	describe: 'Reader written against a later interface',
	provides: [ 'ports' ],
	cost: 'software',
	read: () => ({ collections: { ports: { status: 'ok' } }, rows: [] })
};
