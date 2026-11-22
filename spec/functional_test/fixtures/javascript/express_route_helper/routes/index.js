'use strict';

const express = require('express');
const helpers = require('./helpers');
const writeRoutes = require('./write');
const controllers = require('../controllers');

const { /* page routes */ setupPageRoute } = helpers;
const ARCHIVE = 'archive';

const features = { library: require('./library') };
features.gallery = (app, slug) => {
	app.get(`/preview/${slug}`, (req, res) => res.json(req.query.size));
};

module.exports = function (app) {
	const router = express.Router();

	setupPageRoute(router, '/login', [], controllers.login);
	setupPageRoute(router, '/reset/:code?', [], controllers.reset);
	registerSection(router, 'current');
	registerSection(router, ARCHIVE);
	registerSection(router, runtimeSection());
	registerFixed(router, ARCHIVE);

	const enabled = ['library', 'gallery'];
	const overrides = readConfiguration();
	enabled.forEach(key => {
		if (!(key in overrides)) overrides[key] = key;
	});
	features.gallery(router, 'featured');
	registerFeatures(router, overrides);
	writeRoutes.reload({ router: router });

	app.use(router);
};

function registerFeatures(router, config) {
	Object.keys(config).forEach(key => {
		features[key](router, config[key]);
	});
}

function registerSection(router, section) {
	router.get(`/sections/${section}/items/:id`, (req, res) => res.json(req.query.view));
}

function registerFixed(router, section) {
	router.post(`/fixed/${section}`, (req, res) => res.sendStatus(204));
}

function runtimeSection() { return process.env.SECTION || 'local'; }
function readConfiguration() { return JSON.parse(process.env.FEATURE_PATHS || '{}'); }
