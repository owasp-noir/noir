import type { NextApiRequest, NextApiResponse } from "next"

const handler = async (req: NextApiRequest, res: NextApiResponse) => {
  if (req.method === "DELETE") {
    const id = req.query.id
    await deleteLocal(id)
    AuditLog.write("next:local")
    return res.status(204).end()
  }

  return res.status(405).end()
}

export default handler
