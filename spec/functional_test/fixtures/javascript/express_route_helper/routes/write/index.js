'use strict';

const Write = module.exports;
const { setupApiRoute } = require('../helpers');
const controllers = require('../../controllers');

Write.reload = async (params) => {
	const { router } = params;

	router.use('/api/v3/users', require('./users')());

	setupApiRoute(router, 'get', '/api/v3/ping', controllers.ping);
};
