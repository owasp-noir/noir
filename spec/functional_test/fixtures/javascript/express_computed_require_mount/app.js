const express = require('express');
const path = require('path');
const petsRouter = require(__dirname + '/routes/pets');
const ownersRouter = require(`${__dirname}/routes/owners`);
const vetsRouter = require(path.join(__dirname, 'routes', 'vets'));
const toysRouter = require(path.resolve(__dirname, "routes/toys"));

const app = express();
app.use('/api/pets', petsRouter);
app.use('/api/owners', ownersRouter);
app.use('/api/vets', vetsRouter);
app.use('/api/toys', toysRouter);

app.listen(3000);
