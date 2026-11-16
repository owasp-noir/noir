const { Elysia } = require('elysia');
new Elysia().get('/cts', () => 'ok');
