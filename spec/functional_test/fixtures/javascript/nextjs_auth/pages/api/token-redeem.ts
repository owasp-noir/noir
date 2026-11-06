import type { NextApiRequest, NextApiResponse } from "next"
import { redeemEmailToken, lookupResetToken } from "../../lib/tokens"

// A token taken from a field is being redeemed, not the caller's credential.
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const record = await redeemEmailToken(req.query.token as string)
  if (!record) {
    return res.status(401).json({ error: "Invalid or expired link" })
  }
  const reset = await lookupResetToken(req.body.token)
  if (!reset) return res.status(401).json({ error: "bad token" })
  res.status(200).json({ ok: true })
}
