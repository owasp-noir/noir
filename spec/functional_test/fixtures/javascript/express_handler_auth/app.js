const express = require('express')
const formidable = require('formidable')
const config = require('./lib/config')
const response = require('./lib/response')
const controllers = require('./lib/controllers')
const { setReturnToFromReferer } = require('./lib/utils')

const app = express()

app.post('/history/:noteId', controllers.historyPost)
app.get('/me/delete/:token', controllers.deleteUser)
app.get('/new', response.newNote)
app.put('/notes/:noteId', controllers.updateNote)
app.get('/keyed', controllers.keyedOrUser)
app.get('/either', controllers.eitherBranch)
app.get('/public', controllers.publicFallback)
app.get('/next', controllers.nextRoute)
app.post('/refused', controllers.refusedFirst)
app.get('/counted', controllers.counted)
app.get('/preview', controllers.previewFirst)
app.get('/lookup/:id', controllers.lookupFirst)

// A check inside a promise callback: the name stands in for it.
app.get('/later', (req, res) => {
  Note.findOne({ id: 1 }).then((note) => {
    if (!req.isAuthenticated()) {
      return res.status(403).send('forbidden')
    }
    res.json(note)
  })
})

app.get('/logout', function (req, res, next) {
  if (config.debug && req.isAuthenticated()) {
    console.log('user logout: ' + req.user.id)
  }
  req.logout(() => res.redirect('/'))
})

app.post('/login', function (req, res, next) {
  if (!req.body.email) return response.errorBadRequest(req, res)
  setReturnToFromReferer(req)
  res.redirect('/')
})

app.post('/upload', function (req, res) {
  const form = new formidable.IncomingForm()
  form.parse(req, function (err, fields, files) {
    if (err || !files.image) return res.status(400).end()
    res.send({ name: fields.title, path: files.image.filepath, n: files.length })
  })
})

module.exports = app
