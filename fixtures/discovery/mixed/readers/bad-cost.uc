// Cost outside the declared vocabulary, so the aggregate cost warning could
// not be computed.
return {
	id: 'bad-cost',
	api: 1,
	describe: 'Reader with an unknown cost',
	provides: [ 'ports' ],
	cost: 'cheap',
	read: () => ({ collections: { ports: { status: 'ok' } }, rows: [] })
};
