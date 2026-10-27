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
