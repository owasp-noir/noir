const express = require('express');
const { usersRouter } = require('./routes/users');
const { router: postsRouter } = require('./routes/posts');
const tags = require('./routes/tags');
const { adminRouter, auditRouter } = require('./routes/admin');
const { apiRouter } = require('./routes/api');

const app = express();
app.use('/users', usersRouter);
app.use('/posts', postsRouter);
app.use('/tags', tags.router);
app.use('/admin', adminRouter);
app.use('/audit', auditRouter);
app.use('/api', apiRouter);
