'use strict';

const express = require('express');
const helpers = require('./helpers');
const writeRoutes = require('./write');
const controllers = require('../controllers');

const { setupPageRoute } = helpers;

module.exports = function (app) {
	const router = express.Router();

	setupPageRoute(router, '/login', [], controllers.login);
	setupPageRoute(router, '/reset/:code?', [], controllers.reset);

	writeRoutes.reload({ router: router });

	app.use(router);
};
