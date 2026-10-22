import express from 'express';

export const router = express.Router();
const comfy = express.Router();
const deep = express.Router();

router.get('/top', (req, res) => res.json({}));
comfy.post('/ping', (req, res) => res.json({}));
deep.get('/leaf', (req, res) => res.json({}));

comfy.use('/deep', deep);
router.use('/comfy', comfy);
