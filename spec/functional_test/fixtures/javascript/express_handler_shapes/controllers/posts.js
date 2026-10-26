const Posts = module.exports;

Posts.summary = async (req, res) => {
	const list = await load(req.query.summaryOnly);
	res.json(list);
};

Posts.list = async (req, res) => {
	res.json({ page: req.query.page });
};

async function load(x) { return [x]; }
