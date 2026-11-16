import type { NextApiRequest, NextApiResponse } from 'next'
import { withAuth } from '../../lib/pagesAuth'

async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== 'GET') return res.status(405).end()
  res.json([])
}

export default withAuth(handler)
