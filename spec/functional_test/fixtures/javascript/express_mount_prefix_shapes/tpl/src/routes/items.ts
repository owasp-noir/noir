import express from 'express'
const router = express.Router()
router.get('/:version/list', (req: express.Request, res: express.Response) => {
  res.json([])
})
module.exports = router
