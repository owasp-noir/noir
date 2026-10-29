export async function GET(req: Request, { params }: { params: Promise<{ nextauth: string[] }> }) {
  const { nextauth } = await params
  return Response.json({ parts: nextauth })
}
