import type { NextApiRequest, NextApiResponse } from "next"

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  // The dynamic segment, read through req.query.
  const itemId = Number(req.query.itemId)

  if (req.method === "GET") {
    const sort = req.query.sort
    return res.status(200).json({ itemId, sort })
  } else if (req.method === "PUT") {
    const name = req.body.name
    return res.status(200).json({ itemId, name })
  } else if (req.method === "DELETE" || req.query.force) {
    // Not a single verb test: read for every verb.
    const reason = req.body.reason
    return res.status(204).end(reason)
  }
}
