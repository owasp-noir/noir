import { Elysia } from 'elysia'

// The constructor prefix applies to every route on the instance, including
// routes of an inline plugin instance mounted with .use().
export const admin = new Elysia({ prefix: '/admin' })
    .get('/stats', ({ query }) => query.range)
    .use(new Elysia({ prefix: '/audit' }).get('/log', () => []))
