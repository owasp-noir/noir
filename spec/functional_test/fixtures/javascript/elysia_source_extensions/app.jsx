import { Elysia } from 'elysia';
new Elysia().get('/jsx', () => <span>ok</span>);
