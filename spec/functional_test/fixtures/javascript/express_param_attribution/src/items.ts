import express from 'express'

export default (base) => {
  const router = express.Router()
  router.get('/a', async (req, res) => {
    res.json(req.query.qa)
  })
  router.get('/b', async (req, res) => {
    res.json(req.query.qb)
  })
  return router
}
