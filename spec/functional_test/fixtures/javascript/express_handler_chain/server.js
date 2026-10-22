const express = require('express')
const multer = require('multer')
const { requireAuth, ensureFile, checkType, handleZip, handleXml, handleYaml } = require('./routes/upload')

const app = express()
const upload = multer()

// Each step handles one file type and passes the rest on with next():
// the zip write happens in handleZip, not in the last argument.
app.post('/upload', upload.single('file'), express.json(), ensureFile, checkType, handleZip, handleXml, handleYaml)

// A guard-only registration: no handler, so no step contributes callees.
app.put('/upload', ensureFile, requireAuth)

// An inline handler after a named step.
app.post('/notes', checkType, (req, res) => {
  res.send(req.body.note)
})

// A path-mounted handler after a named step.
app.use('/legacy-upload', checkType, handleYaml)

app.listen(3000)
