import { Hono } from 'hono'
import { books } from './books'
import authRoutes from './auth'
import { createCounter } from './counter'

const app = new Hono()

app.route('/books', books)
app.route('/api/auth', authRoutes)
app.on('GET', '/healthz', (c) => c.text('ok'))

app.route('/fixed', createCounter())
app.route(process.env.COUNTER_PATH ?? '/seasonal', createCounter())

export default app
