'use strict';

module.exports = {
	login: (req, res) => res.render('login'),
	reset: (req, res) => res.render('reset'),
	ping: (req, res) => res.json({ pong: true }),
	users: {
		get: (req, res) => res.json({}),
		update: (req, res) => res.json({}),
		revokeToken: (req, res) => res.sendStatus(200),
		export: (req, res) => res.sendStatus(200),
	},
};
