import type { NextApiRequest, NextApiResponse } from "next"

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method === "POST") {
    const username = req.body.username
    const password = req.body.password
    res.status(200).json({ ok: true, username, password })
    return
  }
  res.status(405).end()
}
