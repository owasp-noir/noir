export async function GET(request: Request) {
  const limit = new URL(request.url).searchParams.get("limit");
  return Response.json({ limit, users: [] });
}

export async function POST(request: Request) {
  const { name, email } = await request.json();
  return Response.json({ name, email });
}
