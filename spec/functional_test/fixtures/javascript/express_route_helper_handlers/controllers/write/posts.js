'use strict';

const pagination = require('../../pagination');

const Posts = module.exports;

Posts.get = async (req, res) => {
	res.json({ pid: req.params.pid });
};

Posts.vote = async (req, res) => {
	res.json({ delta: req.body.delta });
};

Posts.mine = async (req, res) => {
	res.json({ uid: req.uid });
};

Posts.pagination = async (req, res) => {
	res.json(pagination.create(req.query.page));
};

Posts.feed = async function (req, res) {
	const uid = await uidFromToken(req, res);
	res.json({ tid: req.params.tid, uid });
};

async function uidFromToken(request, res) {
	delete request.query.lang;
	return request.query.uid || 0;
}
