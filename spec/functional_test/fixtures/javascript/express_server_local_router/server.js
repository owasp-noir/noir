const express = require('express');
const usersRouter = require('./routes/users');
const postsRouter = require('./routes/posts');

const server = express();
const apiRouter = express.Router();

server.use(express.json());

apiRouter.use('/users', usersRouter);
server.use('/api', apiRouter);
server.use('/posts', postsRouter);

server.listen(3000);
