'use strict';

const helpers = module.exports;
const middleware = require('../middleware');

// router, verb, name, middlewares(optional), controller
helpers.setupApiRoute = function (...args) {
	const [router, verb, name] = args;
	let middlewares = args.length > 4 ? args[args.length - 2] : [];
	const controller = args[args.length - 1];
	middlewares = [middleware.authenticateRequest, ...middlewares];

	router[verb](name, middlewares, helpers.tryRoute(controller, (err, res) => {
		res.status(400).json({ error: err.message });
	}));
};

helpers.tryRoute = function (controller, handler) {
	if (controller && controller.constructor && controller.constructor.name === 'AsyncFunction') {
		return async function (req, res, next) {
			try {
				await controller(req, res, next);
			} catch (err) {
				if (handler) {
					return handler(err, res);
				}
				next(err);
			}
		};
	}
	return controller;
};
