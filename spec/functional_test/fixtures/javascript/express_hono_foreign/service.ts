// A Hono handler file in the same repo. It uses the same `.get()/.post()`
// chaining shape Express's shared route extractor recognizes, but never
// mentions express. The Express analyzer must NOT claim it (mislabeling
// its routes js_express); the Hono analyzer owns it (#2368).
import { Hono } from 'hono'

const app = new Hono()

app.get('/hono-items', (c) => c.json([]))
app.post('/hono-items', (c) => c.json({}))

export default app
