import type { NextApiRequest, NextApiResponse } from 'next'
import { withTiming } from '../../lib/pagesAuth'

async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== 'GET') return res.status(405).end()
  res.json({ ok: true })
}

export default withTiming(handler)
