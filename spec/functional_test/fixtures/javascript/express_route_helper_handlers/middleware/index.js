'use strict';

const middleware = module.exports;

const controllers = {
	helpers: require('../controllers/helpers'),
};

// Looks the caller up; never refuses one.
middleware.authenticateRequest = async (req, res, next) => {
	req.loggedIn = Boolean(req.session && req.session.uid);
	next();
};

// Passes every request on; it serves nothing.
middleware.markApi = (req, res, next) => {
	res.locals.isAPI = true;
	next();
};

middleware.mustBeMember = (req, res, next) => {
	if (!req.loggedIn) {
		return controllers.helpers.notAllowed(req, res);
	}
	next();
};

// Answers guests with nothing; that is an answer, not a refusal.
middleware.emptyForGuests = (req, res, next) => {
	if (!req.loggedIn) {
		return res.status(204).end();
	}
	next();
};

middleware.assertPost = (req, res, next) => {
	if (!req.params.pid) {
		return res.status(404).json({ error: 'no-post' });
	}
	next();
};
