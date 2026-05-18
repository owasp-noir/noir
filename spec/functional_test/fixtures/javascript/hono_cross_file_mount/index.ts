import { Hono } from 'hono'
import api from './api'

const app = new Hono()

app.get('/', (c) => c.text('Pretty Blog API'))
app.route('/api', api)

export default app
