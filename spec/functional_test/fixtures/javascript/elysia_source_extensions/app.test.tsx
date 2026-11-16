import { Elysia } from 'elysia';
new Elysia().get('/test-only', () => <span>test</span>);
