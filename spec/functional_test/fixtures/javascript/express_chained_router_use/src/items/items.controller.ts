import { Router } from 'express';
const router = Router();
router.get('/items', (req, res) => { res.json([]) });
export default router;
