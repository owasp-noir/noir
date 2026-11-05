import type { NextApiRequest, NextApiResponse } from "next"

// A type check of the submitted body is not a caller check.
export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  const input = parseInput(req.body)
  if (typeof input === "string") {
    return res.status(401).json({ response: input })
  }
  res.status(200).json(input)
}

function parseInput(body: unknown) {
  return typeof body === "object" ? body : "bad"
}
