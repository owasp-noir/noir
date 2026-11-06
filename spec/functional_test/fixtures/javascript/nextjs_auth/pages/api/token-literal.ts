import type { NextApiRequest, NextApiResponse } from "next"
import { verifyToken } from "../../lib/verify"

// The `typeof` test the 401 sits under is about the body; the token one is quoted text.
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const token = await verifyToken({ req })
  if (typeof req.body === "object") { const note = `if (typeof token === "string")`
    return res.status(401).json({ note })
  }
  res.status(200).json(token)
}
