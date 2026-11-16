const express = require('express')
const asyncHandler = require('express-async-handler')
const UserController = require('./controllers/userController')
const { AccountController } = require('./controllers/accountController')

const app = express()
const users = new UserController()
const accounts = new AccountController()

app.get('/users', asyncHandler(users.list.bind(users)))
app.post('/users', asyncHandler(users.create.bind(users)))
app.get('/users/:id', users.show)
app.post('/accounts/login', accounts.login)
// Inherited from BaseController: not followed, so no handler is claimed.
app.get('/accounts/ping', accounts.ping)

module.exports = app
