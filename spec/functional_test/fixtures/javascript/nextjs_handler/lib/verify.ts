import type { NextApiRequest, NextApiResponse } from "next";

export async function handler(req: NextApiRequest, res: NextApiResponse) {
  res.status(200).json({ verified: true });
}
