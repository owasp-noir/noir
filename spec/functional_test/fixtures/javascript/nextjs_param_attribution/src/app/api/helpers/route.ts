import { withErrors } from '@/util/route'

const norm = (s: string) => s.trim()

function buildRedirect(target: string) {
  return new URL(target).searchParams.get('next')
}

export const PUT = withErrors(async (req: Request) => {
  const owner = norm(req.headers.get('x-owner-id') ?? '')
  return Response.json({ owner, to: buildRedirect('/home') })
})

export const DELETE = withErrors(async (req: Request) => {
  const tenant = req.headers.get('x-tenant-id')
  return Response.json({ tenant })
})
