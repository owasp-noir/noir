import express, { Request, Response } from 'express';

const app = express();
const router = express.Router();

interface Params { id: string }
interface Body { name: string }
interface Query { verbose?: string }

router.get('/x00-control/:id', (req, res) => {
  res.json({ v: req.query.verbose });
});

router.get<Params, unknown, unknown, Query>('/x01-generic/:id', (req, res) => {
  res.json({ v: req.query.verbose });
});

router.post<Params, unknown, Body>('/x02-generic/:id', async (req, res) => {
  const { name } = req.body;
  res.json({ name, t: req.headers['x-tenant'] });
});

app.get<{ id: string }>('/x03-inline/:id', (req, res) => {
  res.json({ c: req.cookies.sid });
});

app.use('/api', router);
