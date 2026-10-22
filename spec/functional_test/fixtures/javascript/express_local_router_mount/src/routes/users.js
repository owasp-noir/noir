const express = require('express');
const router = express.Router();
const ctrl = require('../controllers/users');

router.param('userId', (req, res, next, id) => { next(); });

router
  .route('/:userId')
  .get(ctrl.show)
  .put(ctrl.update)
  .delete(ctrl.remove);

router.get('/', (req, res) => {
  const { page, limit } = req.query;
  res.json({ page, limit });
});

router.post('/', (req, res) => {
  const { name, email } = req.body;
  const token = req.get('X-Api-Token');
  res.status(201).json({ name, email, token });
});

module.exports = router;
