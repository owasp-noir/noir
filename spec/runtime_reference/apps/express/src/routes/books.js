const express = require('express');
const books = express.Router();

const reply = (_req, res) => res.send('books');
const mark = (_req, res, next) => { res.set('X-Catalog', 'books'); next(); };

books.use(mark);
books.get('/books', reply);
books.post('/books', mark, reply);
books.get('/books/:id', reply);
books.patch('/books/:id', reply);
books.get('/editions{/:year}', reply);
books.get('/files/*parts', reply);
books.get('/authors/:"author-name"', reply);

module.exports = { books, reply, mark };
