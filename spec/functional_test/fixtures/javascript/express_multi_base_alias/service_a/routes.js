const express = require('express')
const router = express.Router()

router.get('/route-a', (_req, res) => res.json({ ok: true }))

module.exports = router
