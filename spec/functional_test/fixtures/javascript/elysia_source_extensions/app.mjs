import { Elysia } from 'elysia';
new Elysia().get('/mjs', () => 'ok');
