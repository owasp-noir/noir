import { withErrors } from '@/util/route'

export const PUT = withErrors(async (req: Request) => {
  const owner = req.headers.get('x-owner-id')
  return Response.json({ owner })
})

export const DELETE = withErrors(async (req: Request) => {
  const tenant = req.headers.get('x-tenant-id')
  return Response.json({ tenant })
})

export async function GET(req: Request) {
  const page = new URL(req.url).searchParams.get('page')
  return Response.json({ page })
}
