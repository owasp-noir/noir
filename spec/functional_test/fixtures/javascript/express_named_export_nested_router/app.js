import express from 'express';
import { router as sd } from './routes/sd.js';
import { router as speech } from './routes/speech.js';

const app = express();
app.use('/api/sd', sd);
app.use('/api/speech', speech);
