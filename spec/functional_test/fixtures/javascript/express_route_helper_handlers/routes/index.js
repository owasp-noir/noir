'use strict';

const express = require('express');
const helpers = require('./helpers');
const controllers = require('../controllers');
const middleware = require('../middleware');

const _mounts = {
	feed: require('./feed'),
};

// `name` comes from whoever calls this: the prefix is a variable.
_mounts.post = (app, name) => {
	app.get(`/${name}/:pid`, helpers.tryRoute(controllers.write.posts.get));
};

// Two modules register `/${name}`: one row, two handlers.
_mounts.tags = (app, name) => {
	app.get(`/${name}`, helpers.tryRoute(controllers.write.posts.mine));
};
_mounts.users = (app, name) => {
	app.get(`/${name}`, helpers.tryRoute(controllers.write.posts.pagination));
};

module.exports = function (app) {
	const router = express.Router();
	router.all('/api/v3/*', middleware.markApi);

	router.use('/api/v3/posts', require('./write/posts')());
	_mounts.feed(router, controllers);
	helpers.setupApiRoute(router, 'get', '/api/v3/ping', controllers.write.utilities.ping.get);

	app.use(router);
};
