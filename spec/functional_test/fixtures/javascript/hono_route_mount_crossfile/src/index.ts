import { Hono } from 'hono'
import TodoAPI from './todo'

export default new Hono().route('/api', TodoAPI)
