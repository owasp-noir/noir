const fs = require('fs')
const { parseXml } = require('../lib/xml')

function requireAuth (req, res, next) {
  if (!req.headers.authorization) {
    return res.status(401).end()
  }
  next()
}

function ensureFile (req, res, next) {
  if (req.file != null) {
    next()
  } else {
    res.status(400).json({ error: 'File is not passed' })
  }
}

function checkType (req, res, next) {
  const fileType = req.file.originalname.split('.').pop()
  console.log(fileType)
  next()
}

function handleZip (req, res, next) {
  if (!req.file.originalname.endsWith('.zip')) {
    next()
    return
  }
  fs.writeFileSync('uploads/' + req.file.originalname, req.file.buffer)
  res.status(204).end()
}

function handleXml (req, res, next) {
  if (!req.file.originalname.endsWith('.xml')) {
    next()
    return
  }
  const doc = parseXml(req.file.buffer.toString())
  res.status(410).send(doc)
}

function handleYaml (req, res) {
  const text = req.file.buffer.toString()
  res.status(410).send(text)
}

module.exports = { requireAuth, ensureFile, checkType, handleZip, handleXml, handleYaml }
