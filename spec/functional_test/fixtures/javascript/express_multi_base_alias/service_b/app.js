const express = require('express')
const routes = require('@/routes')
const app = express()

app.use('/b', routes)

module.exports = app
