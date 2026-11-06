import type { NextApiRequest, NextApiResponse } from "next"
import { generateToken } from "../../lib/tokens"

// Minting a token off the request is not a check of the caller.
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const token = await generateToken({ req })
  if (typeof token === "string") {
    return res.status(401).json({ error: "could not issue" })
  }
  res.status(200).json({ token })
}
