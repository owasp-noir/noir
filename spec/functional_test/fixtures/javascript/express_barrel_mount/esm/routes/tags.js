import { Router } from 'express';
const router = Router();
router.get('/popular', (req, res) => res.send('ok'));
export default router;
