const express = require('express')
const routes = require('@/routes')
const app = express()

app.use('/a', routes)

module.exports = app
