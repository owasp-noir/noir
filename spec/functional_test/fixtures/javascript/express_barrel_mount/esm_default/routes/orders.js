import { Router } from 'express';
const router = Router();
router.get('/pending', (req, res) => res.send('ok'));
export default router;
