const express = require('express')
const app = express()

app.get('/api/health', (_req, res) => res.json({ ok: true }))
app.use('/assets', express.static('public'))

module.exports = app
