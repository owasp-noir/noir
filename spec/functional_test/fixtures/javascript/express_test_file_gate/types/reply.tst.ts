import express from 'express';

const app = express();
app.get('/phantom-tst', (req, res) => res.json({}));
