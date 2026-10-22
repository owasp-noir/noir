import { Router } from 'express';
export const usersRouter = Router();
usersRouter.get('/list', (req, res) => res.send('users'));
