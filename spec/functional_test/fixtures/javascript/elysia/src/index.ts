import { Elysia } from 'elysia'

const app = new Elysia()
    .get('/users', ({ query }) => {
        const filter = query.filter
        return []
    })
    .post('/users', ({ body }) => body)
    .get('/users/:id', ({ params, headers }) => {
        const trace = headers['x-trace']
        return params.id
    })
    .group('/api/v1', (app) =>
        app
            .get('/health', () => 'ok')
            .post('/submit', ({ body, headers }) => {
                const token = headers['x-token']
                return body
            })
            .get('/items/:itemId', ({ params, query }) => {
                const category = query.category
                return params.itemId
            })
    )
    .delete('/sessions/:id', ({ params, cookie }) => {
        const session = cookie.session
        return null
    })
    .all('/health', () => 'ok')
    .listen(3000)

export default app
