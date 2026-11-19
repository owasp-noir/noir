const express = require('express');
const usersRouter = require('./routes/users');
const postsRouter = require('./routes/posts');
const tagsRouter = require('./routes/tags');

const app = express();

app.use('/api', usersRouter, postsRouter);
app.use('/v2', [usersRouter, tagsRouter]);

const a = express.Router();
const b = express.Router();
a.get('/local-a', (req, res) => res.send('a'));
b.get('/local-b', (req, res) => res.send('b'));
app.use('/same-file', a, b);

app.listen(3000);
