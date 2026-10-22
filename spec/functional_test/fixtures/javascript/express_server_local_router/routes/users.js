const router = require('express').Router();
router.get('/:id', (req, res) => res.json(req.params.id));
module.exports = router;
