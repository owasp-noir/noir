import { Hono } from 'hono'
import { books } from './books'
import authRoutes from './auth'

const app = new Hono()

app.route('/books', books)
app.route('/api/auth', authRoutes)
app.on('GET', '/healthz', (c) => c.text('ok'))

export default app
