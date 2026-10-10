import { Router } from 'express';
const router = Router();
router.get('/list', (req, res) => res.send('ok'));
export default router;
