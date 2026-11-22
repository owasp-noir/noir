'use strict';

const { setupPageRoute } = require('./helpers');

module.exports = function (router, slug) {
	setupPageRoute(router, `/browse/${slug}/:id`, [], (req, res) => res.sendStatus(200));
};
