import type { NextApiRequest, NextApiResponse } from "next"

export default function handler(req: NextApiRequest, res: NextApiResponse) {
  const id = req.query.id
  const token = req.headers["x-token"]
  const session = req.cookies["session"]
  res.status(200).json({ id, token, session })
}
