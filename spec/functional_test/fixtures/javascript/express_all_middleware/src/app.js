const express = require('express')

function requireStaff (req, res, next) {
  if (!req.user) return res.status(401).end()
  next()
}

const app = express()
const router = express.Router()

const appsRouter = express.Router()
router.all(['/apps', '/apps/*'], requireStaff)
router.use('/apps', appsRouter)

appsRouter.get('/installations', (req, res) => res.json([]))
appsRouter.delete('/installations/:id', (req, res) => res.json({ id: req.params.id }))

router.get('/posts', requireStaff, (req, res) => res.json([]))

app.use('/api', router)
