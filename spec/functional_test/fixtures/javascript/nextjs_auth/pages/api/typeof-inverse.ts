import type { NextApiRequest, NextApiResponse } from "next"
import { verifyToken } from "../../lib/verify"

// Refuses the caller whose token checked out: not a caller check.
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const token = await verifyToken({ req })
  // if (typeof token === "string") res.status(401)
  if (typeof token !== "string") {
    return res.status(401).json({ response: "already signed in" })
  }
  res.status(200).json({ ok: true })
}
