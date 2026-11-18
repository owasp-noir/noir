const express = require('express');
const router = express.Router({ mergeParams: true });

// Mounted by a loader this scan cannot follow; the parent supplies :ownerId.
router.get('/list', (req, res) => {
  res.send(req.params.ownerId);
});

module.exports = router;
