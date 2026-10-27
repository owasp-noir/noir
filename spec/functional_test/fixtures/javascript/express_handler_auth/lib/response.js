const config = require('./config')

exports.errorForbidden = errorForbidden
exports.errorBadRequest = errorBadRequest
exports.errorTooLong = errorTooLong
exports.newNote = newNote

function errorForbidden (req, res) {
  if (req.user) {
    responseError(res, '403', 'Forbidden')
  } else {
    res.redirect('/login?next=' + encodeURIComponent(req.originalUrl))
  }
}

function errorBadRequest (req, res) {
  responseError(res, '400', 'Bad Request')
}

function errorTooLong (req, res) {
  responseError(res, '413', 'Payload Too Large')
}

function responseError (res, code, detail) {
  res.status(code).render('error.ejs', { code, detail })
}

function newNote (req, res) {
  let body = ''
  if (req.body && req.body.length > config.documentMaxLength) {
    return errorTooLong(req, res)
  } else if (req.body) {
    body = req.body
  }
  let owner = null
  if (req.isAuthenticated()) {
    owner = req.user.id
  } else if (!config.allowAnonymous) {
    return errorForbidden(req, res)
  }
  res.send({ owner, body })
}
