import type { NextApiRequest, NextApiResponse } from "next"
import { verifyToken } from "../../lib/verify"

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const token = await verifyToken({ req })
  if (typeof token === "string") {
    return res.status(401).json({ response: token })
  }
  res.status(200).json(token)
}
