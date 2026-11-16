import type { NextApiHandler } from 'next'
import { getToken } from 'next-auth/jwt'

export const withAuth = (handler: NextApiHandler): NextApiHandler => async (req, res) => {
  const token = await getToken({ req })
  if (!token) return res.status(401).end()
  return handler(req, res)
}

export const withTiming = (handler: NextApiHandler): NextApiHandler => async (req, res) => {
  const started = Date.now()
  await handler(req, res)
  console.log(req.url, Date.now() - started)
}
