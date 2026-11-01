import { NextRequest, NextResponse } from "next/server";

export async function GET(request: NextRequest) {
  const page = request.nextUrl.searchParams.get("page");
  return NextResponse.json(await listBroken(page));
}

function broken( { return 1 }

export async function POST(request: NextRequest) {
  const { title } = await request.json();
  return NextResponse.json(await saveBroken(title));
}
