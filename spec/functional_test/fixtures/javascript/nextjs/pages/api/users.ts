import type { NextApiRequest, NextApiResponse } from "next"

export default function handler(req: NextApiRequest, res: NextApiResponse) {
  const page = req.query.page
  const limit = req.query.limit
  const search = req.query.search

  const username = req.body.username
  const email = req.body.email

  res.status(200).json({ page, limit, search, username, email })
}
