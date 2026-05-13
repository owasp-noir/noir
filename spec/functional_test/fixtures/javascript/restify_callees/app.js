const restify = require('restify')
const Router = require('restify-router').Router

const server = restify.createServer()
const router = new Router()

server.post('/users/:id', function (req, res, next) {
  const id = req.params.id
  const actor = req.header('X-Actor')
  const payload = parseUser(req)
  serviceFactory().save(payload, id, actor)
  AuditLog.write('restify:create')

  res.send(201, serializeUser(payload))
  return next()
})

function setupRoutes(server) {
  server.get('/health', function (req, res, next) {
    const status = loadHealth()
    res.send(status)
    return next()
  })
}

router.get('/profile', function (req, res, next) {
  const userId = req.query.userId
  const profile = loadProfile(userId)

  res.send(profile)
  return next()
})

function parseUser(req) {
  return req.body
}

function serviceFactory() {
  return userService
}

function serializeUser(payload) {
  return { data: payload }
}

function loadHealth() {
  return { ok: true }
}

function loadProfile(userId) {
  return { userId }
}

setupRoutes(server)
router.applyRoutes(server)
server.listen(3000)
