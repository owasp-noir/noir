import { withSession } from '../../../lib/auth'

export const GET = withSession(async (req, { session }) => {
  return Response.json({ owner: session.user.id })
})
