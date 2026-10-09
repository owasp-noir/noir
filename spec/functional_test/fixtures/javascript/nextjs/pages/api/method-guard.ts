import type { NextApiRequest, NextApiResponse } from "next"

// Early-exit guards: only the methods named in the negated checks get past.
export default function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== 'POST' && req.method != 'PUT') {
    res.setHeader('Allow', ['POST', 'PUT'])
    return res.status(405).json({ error: "Method Not Allowed" })
  }
  res.status(200).json({ ok: true })
}
