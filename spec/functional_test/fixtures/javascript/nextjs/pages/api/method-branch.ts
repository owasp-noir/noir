import type { NextApiRequest, NextApiResponse } from "next"

// Negated checks that do not bound the method: one branches instead of
// rejecting, the other rejects only together with an unrelated condition.
// The default-handler fallback still applies.
export default function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method !== 'GET' && !isSigned(req)) return res.status(401).end()
  if (req.method !== 'GET') {
    return handleWrite(req, res)
  }
  return res.status(200).json({ ok: true })
}

function isSigned(req: NextApiRequest) {
  return false
}

function handleWrite(req: NextApiRequest, res: NextApiResponse) {
  res.status(201).end()
}
