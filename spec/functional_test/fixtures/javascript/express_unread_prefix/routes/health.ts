import express from 'express';
export const health = express.Router();
health.get('/prefix-health', (req, res) => res.send('ok'));
