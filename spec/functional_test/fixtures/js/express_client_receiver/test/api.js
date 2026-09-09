'use strict';

// HTTP client calls in a test file. `request.get(url, opts)` has the same
// token shape as `router.get(path, handler)`, so these used to be
// reported as routes of this application.
const request = require('../lib/request');
const assert = require('assert');

describe('api', () => {
	it('reads a user', async () => {
		const { response } = await request.get(`${base}/api/users/1`, opts);
		assert(response);
	});

	it('creates a user', async () => {
		const { response } = await request.post(`${base}/api/users`, { name: 'x' });
		assert(response);
	});

	it('deletes a user', async () => {
		await request.delete(`${base}/api/users/1`, opts);
	});

	it('replaces a user', async () => {
		await request.put(`${base}/api/users/1`, { name: 'y' });
	});
});
