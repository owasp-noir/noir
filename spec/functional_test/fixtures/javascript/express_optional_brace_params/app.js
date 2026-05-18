const express = require('express')
const app = express()

app.all('/user/:id{/:op}', function userAction(req, res) {
  res.send('ok')
})
