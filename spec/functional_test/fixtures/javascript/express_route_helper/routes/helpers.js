'use strict';

const helpers = module.exports;
const middleware = require('../middleware');

// router, verb, name, middlewares(optional), controller
helpers.setupApiRoute = function (...args) {
	const [router, verb, name] = args;
	const middlewares = args.length > 4 ? args[args.length - 2] : [];
	const controller = args[args.length - 1];

	router[verb](name, middlewares, controller);
};

// router, name, middlewares(optional), controller
helpers.setupPageRoute = function (...args) {
	const [router, name] = args;
	const middlewares = args.length > 3 ? args[args.length - 2] : [];
	const controller = args[args.length - 1];

	router.get(name, middleware.buildHeader, middlewares, controller);
	router.get(`/api${name}`, middlewares, controller);
};
