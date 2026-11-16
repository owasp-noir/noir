const { Elysia } = require('elysia');
new Elysia().get('/cjs', () => 'ok');
