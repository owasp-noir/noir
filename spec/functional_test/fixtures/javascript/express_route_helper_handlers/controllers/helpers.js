'use strict';

const helpers = module.exports;

helpers.notAllowed = async function (req, res) {
	if (req.loggedIn) {
		res.status(403).json({ error: 'forbidden' });
	} else {
		res.status(401).json({ error: 'not-logged-in' });
	}
};
