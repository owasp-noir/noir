import { Hono } from 'hono'

const book = new Hono()
book.get('/list', (c) => c.text('List'))
book.get('/:id', (c) => c.text('Detail'))
book.post('/', (c) => c.text('Create'))

const app = new Hono()
app.route('/book', book)

export default app
