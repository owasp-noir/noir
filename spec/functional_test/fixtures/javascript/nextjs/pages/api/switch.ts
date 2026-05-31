import type { NextApiRequest, NextApiResponse } from "next"

export default function handler(req: NextApiRequest, res: NextApiResponse) {
  switch (req.method) {
    case "GET": {
      const { cursor } = req.query
      res.status(200).json({ cursor })
      return
    }
    case "DELETE": {
      const id = req.body.id
      res.status(204).json({ id })
      return
    }
    default:
      res.status(405).end()
  }
}
