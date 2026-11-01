import { NextRequest, NextResponse } from "next/server";
import { withAuth } from "@/lib/auth";
import { saveWrapped, listWrapped } from "@/lib/wrapped";

async function listHandler(request: NextRequest): Promise<{ rows: number[] }> {
  const limit = request.nextUrl.searchParams.get("limit");
  return NextResponse.json(await listWrapped(limit));
}

export const GET = withAuth(listHandler);
export const PUT = (async (request: NextRequest) => {
  const body = await request.json();
  return NextResponse.json(await saveWrapped(body));
}) satisfies (r: NextRequest) => Promise<Response>;
