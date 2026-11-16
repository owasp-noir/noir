const express = require('express');
const fileService = require('../services/fileService');
const reportService = require('../services/reportService');
const { pingA, slugify } = require('../services/text');
const { runDup } = require('shared/dup');
const router = express.Router();

router.get('/read', async (req, res) => {
  const data = await fileService.read(req.query.name);
  res.send(data);
});

router.get('/report', async (req, res) => {
  const rows = await reportService.generate(req.query.name);
  res.json(rows);
});

router.get('/ambiguous', (req, res) => {
  res.json(runDup(req.query.q));
});

router.get('/cycle', (req, res) => {
  res.send(pingA(3));
});

router.get('/slug', (req, res) => {
  res.json({ slug: slugify(req.query.title) });
});

module.exports = router;
