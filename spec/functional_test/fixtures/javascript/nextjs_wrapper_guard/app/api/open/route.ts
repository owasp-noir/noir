import { withPassthrough } from '../../../lib/auth'

export const GET = withPassthrough(async (_req) => {
  return Response.json({ ok: true })
})
