import express from 'express';
import { UserRoute } from './routes/users.route';
import { TwoRoutes } from './routes/two.route';

const app = express();
[new UserRoute(), new TwoRoutes()].forEach((route) => {
  app.use('/', route.router);
});
export default app;
