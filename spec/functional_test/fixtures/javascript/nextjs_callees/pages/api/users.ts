import type { NextApiRequest, NextApiResponse } from "next"

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  if (req.method === "POST") {
    const page = req.query.page
    const user = await parseUser(req)
    await serviceFactory().save(user, page)
    AuditLog.write("next:pages")

    return res.status(200).json(serializeUser(user))
  }

  return res.status(405).end()
}
