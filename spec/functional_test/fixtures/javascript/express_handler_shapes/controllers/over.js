exports.thing = async (req, res) => { res.json({ old: req.query.oldThing }); };
exports.thing = async (req, res) => { res.json({ neu: req.query.newThing }); };
