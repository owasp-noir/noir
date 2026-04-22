import { NextRequest, NextResponse } from "next/server"

export async function GET(request: NextRequest) {
  const theme = request.nextUrl.searchParams.get("theme")
  return NextResponse.json({ theme })
}
