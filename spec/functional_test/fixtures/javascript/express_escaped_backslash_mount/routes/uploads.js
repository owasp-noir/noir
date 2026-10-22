const express = require('express');

// Windows deployments keep uploads on a drive path, so the default root ends
// with an escaped backslash.
const UPLOAD_ROOT = 'C:\\uploads\\';

function createUploadRouter() {
  const router = express.Router();

  router.get('/', (req, res) => res.json({ root: UPLOAD_ROOT }));
  router.post('/', (req, res) => res.json({}));

  return router;
}

module.exports = { UPLOAD_ROOT, createUploadRouter };
