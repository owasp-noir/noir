import express from 'express';
import * as routes from './routes/index.js';
import { posts, tags } from './routes/index.js';

const app = express();
app.use('/users', routes.users);
app.use('/posts', posts);
app.use('/tags', tags);
