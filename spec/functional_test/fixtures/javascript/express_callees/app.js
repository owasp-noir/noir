const express = require('express')

const app = express()
const router = express.Router()

app.post('/users/:id', async (req, res) => {
  const id = req.params.id
  const include = req.query.include
  const user = await parseUser(req)
  await serviceFactory().save(user, id, include)
  AuditLog.write('express:create')

  return res.json(serializeUser(user))
})

router.get('/profile', (req, res) => {
  const sessionId = req.cookies.sessionId
  const profile = loadProfile(sessionId)

  return res.send(profile)
})

app.use('/api', router)

function parseUser(req) {
  return req.body
}

function serviceFactory() {
  return userService
}

function serializeUser(user) {
  return { data: user }
}

function loadProfile(sessionId) {
  return { sessionId }
}
