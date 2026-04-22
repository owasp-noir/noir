import { NextRequest, NextResponse } from "next/server"

export async function POST(request: NextRequest) {
  const formData = await request.formData()
  const file = formData.get("file")
  const description = formData.get("description")
  return NextResponse.json({ ok: true, description })
}
