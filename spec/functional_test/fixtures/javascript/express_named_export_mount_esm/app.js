import express from 'express';
import { usersRouter } from './routes/users.js';
import { postsRouter as posts } from './routes/posts.js';

const app = express();
app.use('/users', usersRouter);
app.use('/posts', posts);
