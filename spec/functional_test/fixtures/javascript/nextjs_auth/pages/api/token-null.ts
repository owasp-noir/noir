import type { NextApiRequest, NextApiResponse } from "next"
import { readJwt } from "../../lib/tokens"

// `typeof null` is "object": this lets a caller without a token through.
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const jwt = await readJwt({ req })
  if (typeof jwt !== "object") {
    return res.status(401).json({ error: "no" })
  }
  res.status(200).json({ ok: true })
}
