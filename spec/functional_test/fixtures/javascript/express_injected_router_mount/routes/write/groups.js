'use strict';

const router = require('express').Router();

module.exports = function () {
	router.get('/:gid', (req, res) => res.json({}));

	return router;
};
