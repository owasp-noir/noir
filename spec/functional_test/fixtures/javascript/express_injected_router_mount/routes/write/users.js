'use strict';

const router = require('express').Router();

module.exports = function () {
	router.get('/:uid', (req, res) => res.json({}));
	router.delete('/:uid', (req, res) => res.sendStatus(200));

	return router;
};
