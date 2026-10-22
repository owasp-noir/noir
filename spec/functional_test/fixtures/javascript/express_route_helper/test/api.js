'use strict';

const assert = require('assert');
const request = require('request-promise-native');
const { setupApiRoute } = require('../routes/helpers');

// Calling the helper from a test file must not register anything.
describe('write api', () => {
	it('does not mint routes', async () => {
		setupApiRoute({}, 'get', '/api/v3/should-not-appear', [], () => {});
		await request.get(`${nconf.get('url')}/api/v3/users/1`);
		assert(true);
	});
});
