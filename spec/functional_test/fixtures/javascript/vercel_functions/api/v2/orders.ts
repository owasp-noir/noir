// Web-standard method exports.
export function GET(request: Request) {
  const status = new URL(request.url).searchParams.get("status");
  return Response.json({ status });
}

export async function POST(request: Request) {
  const { sku, quantity } = await request.json();
  return Response.json({ sku, quantity }, { status: 201 });
}
