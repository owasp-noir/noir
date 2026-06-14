import express from 'express';
// TypeScript ESM (moduleResolution: NodeNext) imports its OWN sibling
// `.ts` sources through a `.js` specifier. The files on disk are
// `controllers/users.ts` and `controllers/posts.ts`.
import usersRouter from './controllers/users.js';
import postsRouter from './controllers/posts.js';

const app = express();

app.use('/users', usersRouter);
app.use('/posts', postsRouter);

app.listen(3000);
