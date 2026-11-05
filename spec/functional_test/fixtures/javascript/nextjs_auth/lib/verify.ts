import type { NextApiRequest, NextApiResponse } from "next"

// Answers an error message in place of the token when there is none.
export async function verifyToken({ req }: { req: NextApiRequest }) {
  const token = await readToken(req)
  if (!token?.id) return "You must be logged in."
  return token
}

export async function verifyUser({ req, res }: { req: NextApiRequest; res: NextApiResponse }) {
  const token = await verifyToken({ req })
  if (typeof token === "string") {
    res.status(401).json({ response: token })
    return null
  }
  return token
}

async function readToken(req: NextApiRequest): Promise<{ id?: number } | null> {
  return req.headers.authorization ? { id: 1 } : null
}
