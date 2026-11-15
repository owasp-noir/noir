import express from 'express';
export function build() {
  const router = express.Router();
  router.get('/prefix-factory', (req, res) => res.send('ok'));
  return router;
}
