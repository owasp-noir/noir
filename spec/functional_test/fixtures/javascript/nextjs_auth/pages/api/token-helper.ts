import type { NextApiRequest, NextApiResponse } from "next"
import { verifyUser } from "../../lib/verify"

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const user = await verifyUser({ req, res })
  if (!user) return
  res.status(200).json(user)
}
