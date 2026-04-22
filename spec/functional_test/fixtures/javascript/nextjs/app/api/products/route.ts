import { NextRequest, NextResponse } from "next/server"

export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams.get("q")
  return NextResponse.json({ q })
}

export async function POST(request: NextRequest) {
  const body = await request.json()
  return NextResponse.json({ ok: true, body })
}
