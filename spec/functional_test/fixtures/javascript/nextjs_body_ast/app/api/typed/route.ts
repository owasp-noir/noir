import { NextRequest, NextResponse } from "next/server";
import { loadTyped } from "@/lib/typed";

export async function GET(request: NextRequest): Promise<NextResponse<{ ok: true; items: string[] }>> {
  const page = request.nextUrl.searchParams.get("page");
  return NextResponse.json(await loadTyped(page));
}

export const POST = async (request: NextRequest): Promise<NextResponse<{ saved: boolean }>> => {
  const body = await request.json();
  return NextResponse.json(await loadTyped(body.title));
};
