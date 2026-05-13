import type { NextApiRequest, NextApiResponse } from "next"

export default async (req: NextApiRequest, res: NextApiResponse) => {
  if (req.method === "GET") {
    const token = req.headers["x-token"]
    const value = await loadArrow(token)
    return res.json(value)
  }

  return res.status(405).end()
}
