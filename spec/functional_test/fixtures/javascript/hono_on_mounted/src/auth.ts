import { Hono } from 'hono'
import { auth } from './lib/auth'

const authRoutes = new Hono()

authRoutes.on(['POST', 'GET'], '/*', (c) => auth.handler(c.req.raw))

export default authRoutes
