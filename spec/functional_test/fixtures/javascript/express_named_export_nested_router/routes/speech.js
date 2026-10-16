import express from 'express';

const router = express.Router();
const eleven = express.Router();

router.get('/health', (req, res) => res.json({}));
eleven.post('/voices', (req, res) => res.json({}));

router.use('/elevenlabs', eleven);

export { router };
