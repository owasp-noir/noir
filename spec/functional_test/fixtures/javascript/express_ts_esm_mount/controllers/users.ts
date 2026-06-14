import express from 'express';

const router = express.Router();

router.get('/me', (req, res) => res.json({}));
router.get('/:id', (req, res) => res.json({}));

export default router;
