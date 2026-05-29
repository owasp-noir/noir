import { cookies, headers } from "next/headers"
import { NextRequest, NextResponse } from "next/server"

export async function POST(request: NextRequest) {
  const form = await request.formData()
  const avatar = form.get("avatar")
  const cookieStore = await cookies()
  const session = cookieStore.get("session")
  const forwarded = headers().get("x-forwarded-for")

  return NextResponse.json({ avatar, session, forwarded })
}
