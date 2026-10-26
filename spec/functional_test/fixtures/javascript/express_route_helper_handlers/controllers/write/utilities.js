'use strict';

const Utilities = module.exports;

Utilities.ping = {};
Utilities.ping.get = (req, res) => {
	res.json({ pong: true });
};
