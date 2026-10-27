const config = require('./config')
const { errorForbidden } = require('./response')

function historyPost (req, res) {
  if (req.isAuthenticated()) {
    res.send({ id: req.params.noteId, pinned: req.body.pinned })
  } else {
    return errorForbidden(req, res)
  }
}

exports.deleteUser = async (req, res) => {
  if (!req.isAuthenticated()) {
    return errorForbidden(req, res)
  }
  res.send({ token: req.params.token })
}

// A setting lets anonymous callers in: no guard.
exports.updateNote = async (req, res) => {
  if (req.isAuthenticated() || config.allowAnonymousEdits) {
    res.send({ ok: true })
  } else {
    return errorForbidden(req, res)
  }
}

// A caller with the right query passes the `else if`: no guard.
exports.keyedOrUser = (req, res) => {
  if (req.user) {
    res.send({ user: req.user.id })
  } else if (req.query.key !== 'secret') {
    return errorForbidden(req, res)
  }
  res.send({ ok: true })
}

// A caller taking the first branch never meets the check: no guard.
exports.eitherBranch = (req, res) => {
  if (req.query.preview) {
    res.locals.preview = true
  } else if (!req.user) {
    return res.status(401).json({ error: 'login' })
  }
  res.send({ ok: true })
}

exports.historyPost = historyPost

let hits = 0

// A lookup that is handed no response cannot answer before the check.
exports.lookupFirst = async (req, res) => {
  const note = await Note.findOne({ id: req.params.id })
  if (!req.user) {
    return res.sendStatus(401)
  }
  res.json(note)
}

// The `else` serves public notes; its `next(err)` is a callback's.
exports.publicFallback = (req, res, next) => {
  if (req.user) {
    res.json({ mine: true })
  } else {
    Note.find({ public: true }, (err, notes) => {
      if (err) return next(err)
      res.json(notes)
    })
  }
}

// `next('route')` hands the request on: no guard.
exports.nextRoute = (req, res, next) => {
  if (req.user) {
    res.json({ me: req.user.id })
  } else {
    next('route')
  }
}

// The first branch refuses too, so every caller meets the check.
exports.refusedFirst = (req, res) => {
  if (!req.body.name) {
    throw new Error('bad')
  } else if (!req.user) {
    throw new Error('unauth')
  }
  res.json({ ok: 1 })
}

// The route decides the path test: on `/status` the first branch is
// never taken, so every caller meets the check; on `/health` it always is.
exports.pathFirst = (req, res) => {
  if (req.path === '/health') {
    res.locals.health = true
  } else if (!req.user) {
    return res.sendStatus(401)
  }
  res.json({ ok: 1 })
}

// A counter is not a setting: no guard.
exports.counted = (req, res) => {
  if (req.user) {
    return res.json({ me: 1 })
  } else if (hits > 100) {
    return res.sendStatus(403)
  }
  hits++
  res.json({ public: 1 })
}

function renderPreview (req, res) {
  if (!req.query.preview) return res.status(404).send('nf')
  res.send('preview')
}

// The earlier exit serves a preview to anyone: no guard.
exports.previewFirst = (req, res) => {
  if (req.query.preview) {
    return renderPreview(req, res)
  }
  if (!req.user) {
    return res.sendStatus(401)
  }
  res.json({ ok: 1 })
}
