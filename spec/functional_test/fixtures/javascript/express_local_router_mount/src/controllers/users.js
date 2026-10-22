exports.show=(req,res)=>res.json(req.params.userId); exports.update=(req,res)=>res.json(req.body.name); exports.remove=(req,res)=>res.end();
