import type { NextApiRequest, NextApiResponse } from "next"

export default function handler(req: NextApiRequest, res: NextApiResponse) {
  switch (req.query.type) {
    case "GET":
      res.status(200).json({ type: "query-get" })
      return
    default:
      res.status(200).json({ ok: true })
  }
}
