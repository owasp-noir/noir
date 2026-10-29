import express from 'express'

export default (basePath: string) => {
  const router = express.Router()
  router.get('/list', (req, res) => {
    const { q } = req.query
    res.json({ basePath, q })
  })
  router.get('/detail', (req, res) => {
    const { sid } = req.cookies
    res.json({ sid })
  })
  return router
}
