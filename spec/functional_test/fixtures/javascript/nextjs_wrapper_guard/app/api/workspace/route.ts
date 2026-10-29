import { withWorkspace } from '../../../lib/auth'

export const GET = withWorkspace(async (_req, { session }) => {
  return Response.json({ owner: session.user.id })
})
