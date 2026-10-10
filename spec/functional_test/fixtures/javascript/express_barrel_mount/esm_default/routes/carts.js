import { Router } from 'express';
const router = Router();
router.get('/current', (req, res) => res.send('ok'));
export default router;
