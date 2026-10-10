import { Router } from 'express';
const router = Router();
router.get('/recent', (req, res) => res.send('ok'));
export default router;
