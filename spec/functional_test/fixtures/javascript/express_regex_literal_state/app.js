const express = require('express')
const app = express()

// A regex literal whose body contains a quote. The lexer used to read this
// '/' as division, after which the quote opened a string token that ran to
// end of file — every route in the file was lost.
const hasQuote = (s) => /["']/.test(s)

app.get('/users', (req, res) => res.json([hasQuote('a')]))

app.post('/items', (req, res) => {
  if (!/['"]/.test(req.body.name)) {
    return res.status(400).json({})
  }
  return res.json({})
})

// No semicolons anywhere (StandardJS style). The chained-verb walk used to
// stop only at a ';', so it ran on into the next statements and hung their
// verbs on /profile as well.
app.route('/profile')
  .get((req, res) => res.json({}))

app.post('/orders', (req, res) => res.json({}))
app.delete('/carts', (req, res) => res.json({}))
