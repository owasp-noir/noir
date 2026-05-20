import { NextRequest, NextResponse } from "next/server"

export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams.get("q")
  const page = request.nextUrl.searchParams.get("page")
  return NextResponse.json({ q, page })
}

export async function POST(request: NextRequest) {
  const body = await request.json()
  const username = body.username
  return NextResponse.json({ username })
}
