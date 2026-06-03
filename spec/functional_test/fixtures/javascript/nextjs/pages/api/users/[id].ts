import type { NextApiRequest, NextApiResponse } from "next"

const SIGNATURE_HEADER = "stripe-signature"
const SESSION_COOKIE = "session-token"

export default function handler(req: NextApiRequest, res: NextApiResponse) {
  const id = req.query.id
  const token = req.headers["x-token"]
  const sig = req.headers[SIGNATURE_HEADER]
  const session = req.cookies["session"]
  const tok = req.cookies[SESSION_COOKIE]
  res.status(200).json({ id, token, sig, session, tok })
}
