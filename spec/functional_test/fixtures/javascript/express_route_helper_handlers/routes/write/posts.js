'use strict';

const router = require('express').Router();
const middleware = require('../../middleware');
const controllers = require('../../controllers');
const { setupApiRoute } = require('../helpers');

module.exports = function () {
	const middlewares = [middleware.mustBeMember];

	setupApiRoute(router, 'get', '/:pid', [middleware.assertPost], controllers.write.posts.get);
	setupApiRoute(router, 'put', '/:pid/vote', [...middlewares, middleware.assertPost], controllers.write.posts.vote);
	setupApiRoute(router, 'get', '/:pid/mine', [middleware.emptyForGuests], controllers.write.posts.mine);
	setupApiRoute(router, 'get', '/:pid/pagination', [], controllers.write.posts.pagination);

	return router;
};
