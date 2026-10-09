const express = require('express');
const app = express();
const items = require('./routes/items');

const local = express.Router();
local.get('', (req, res) => res.send('orders'));
local.post('/', (req, res) => res.send('created'));

app.get('', (req, res) => res.send('home'));
app.use('/orders', local);
app.use('/items', items);
app.listen(3000);
