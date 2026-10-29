export async function GET(req: Request, { params }: { params: Promise<{ seed?: string[] }> }) {
  const { seed } = await params
  return Response.json({ seed: seed?.[0] ?? 'default' })
}
