import express from 'express'
const router = express.Router()
router.get('/404', (req, res) => { res.send('x') })
export default router
