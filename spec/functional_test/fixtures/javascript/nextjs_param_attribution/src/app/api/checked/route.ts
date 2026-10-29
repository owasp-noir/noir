import { withAuth } from '@/util/route'

function validateRequest(req: Request) {
  return req.headers.get('x-api-key') !== null
}

async function postHandler(req: Request) {
  validateRequest(req)
  const { name } = await req.json()
  return Response.json({ name })
}

export const POST = withAuth(postHandler)

export async function GET(req: Request) {
  const sort = new URL(req.url).searchParams.get('sort')
  return Response.json({ sort })
}
