const express = require('express')
const app = express()
app.use(express.json())

// Each handler puts multi-byte text right where a 120-byte look-ahead ends:
// after the `)` of `json({ ... })`, and after the `}` of a destructuring.
app.post('/login', (req, res) => {
  if (!req.body.id) return res.status(400).json({ code: -1 }); const note = '가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가'
  res.json({ id: req.body.id, note })
})

app.post('/signup', (req, res) => {
  const { email } = req.body; const msg = '가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가가'
  res.json({ email, msg })
})

app.get('/health', (req, res) => res.send('ok'))

app.listen(3000)
