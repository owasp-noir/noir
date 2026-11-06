import type { NextApiRequest, NextApiResponse } from 'next'
import { Verb, answer } from '../../utils/respond'

// answer(Verb.DELETE, req, res, {})
const handler = (req: NextApiRequest, res: NextApiResponse): void => {
  if (req.method === 'PUT') {
    res.status(200).json({ saved: true })
    return
  }
  if (answer(Verb.GET, req, res, { a: 1 })) return
  answer('POST', req, res, { b: 2 })
}

export default handler
