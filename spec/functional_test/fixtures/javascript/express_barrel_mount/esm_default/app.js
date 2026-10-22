import express from 'express';
import routes from './routes/index.js';

const app = express();
app.use('/orders', routes.orders);
app.use('/carts', routes.carts);
