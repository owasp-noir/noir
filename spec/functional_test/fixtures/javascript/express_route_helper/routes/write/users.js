'use strict';

const router = require('express').Router();
const controllers = require('../../controllers');
const routeHelpers = require('../helpers');

const { setupApiRoute } = routeHelpers;

module.exports = function () {
	setupApiRoute(router, 'get', '/:uid', [], controllers.users.get);
	setupApiRoute(router, 'put', '/:uid', [], controllers.users.update);
	setupApiRoute(router, 'delete', '/:uid/tokens/:token', [], controllers.users.revokeToken);

	// A commented-out registration is not a route.
	// setupApiRoute(router, 'post', '/:uid/ban', [], controllers.users.ban);

	// Neither is one whose path the scanner cannot read.
	setupApiRoute(router, 'get', buildPath('exports'), [], controllers.users.export);

	return router;
};

function buildPath(kind) {
	return `/${kind}`;
}
