import type { AuthenticatedMedusaRequest, MedusaResponse } from "@medusajs/framework/http"

// export const DELETE = async (req, res) => { res.json({ gone: true }) }

export const POST = async (req: AuthenticatedMedusaRequest<{ name: string }>, res: MedusaResponse) => {
  res.json({ name: req.validatedBody.name })
}
