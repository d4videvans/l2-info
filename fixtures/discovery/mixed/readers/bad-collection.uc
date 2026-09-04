// Claims a collection the format does not register: sources are extensible,
// the vocabulary is not.
return {
	id: 'bad-collection',
	api: 1,
	describe: 'Reader claiming an unregistered collection',
	provides: [ 'ports', 'wireless' ],
	cost: 'software',
	read: () => ({ collections: { ports: { status: 'ok' } }, rows: [] })
};
