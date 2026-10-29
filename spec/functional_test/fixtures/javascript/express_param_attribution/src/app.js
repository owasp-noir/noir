const express = require('express')
const multer = require('multer')
const app = express()
const upload = multer({ dest: '/tmp/up' })

app.get('/items', (req, res) => {
  req.headers['X-Tenant-Id'] = 'default'
  req.query.page = '1'
  req.body.owner = 'me'
  res.json([])
})

app.get('/defaults', (req, res) => {
  req.query.sort ||= 'asc'
  if (req.query.limit == '10') res.json([])
  res.json(req.query.sort)
})

app.post('/icons', upload.fields([{ name: 'icon', maxCount: 1 }, { name: 'banner' }]), (req, res) => { res.json(req.files) })
app.post('/avatar', upload.single('avatar'), (req, res) => { res.json(req.file) })
app.post('/photos', upload.array('photos', 3), (req, res) => { res.json(req.files) })

app.listen(3000)
