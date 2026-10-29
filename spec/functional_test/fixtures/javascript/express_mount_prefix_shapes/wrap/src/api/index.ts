import express from 'express'
const router = express.Router()
router.get('/vault', (req, res) => { res.json([]) })
export default router
