import express from 'express';
import { ROUTES, API, AppRoutes } from './constants';

const LOCAL = { health: '/health' };
const app = express();

app.get(LOCAL.health, (req, res) => { res.send('ok'); });
app.get(ROUTES.users, (req, res) => { res.json([]); });
app.put(ROUTES.userById, (req, res) => { res.json(req.body.name); });
app.get(`${ROUTES.users}/export`, (req, res) => { res.send('ok'); });
app.get(AppRoutes.Invoices, (req, res) => { res.json([]); });

const router = express.Router();
router.get('/leaf', (req, res) => { res.send('ok'); });
app.use(API.v1, router);

app.listen(3000);
