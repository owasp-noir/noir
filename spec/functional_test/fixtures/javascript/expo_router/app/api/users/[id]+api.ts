export function GET(request: Request, { id }: Record<string, string>) {
  return Response.json({ id });
}

export async function DELETE(request: Request, { id }: Record<string, string>) {
  const token = request.headers.get("authorization");
  return Response.json({ id, deleted: Boolean(token) });
}
