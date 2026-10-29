export async function GET(req: Request) {
  const session = await getSession(req)
  if (!session) {
    return Response.json({ error: 'unauthorized' }, { status: 401 })
  }
  return Response.json({ owner: session.user.id })
}

async function getSession(_req: Request): Promise<any> {
  return null
}
