import { NextRequest, NextResponse } from "next/server"
import { cookies } from "next/headers"

type Context = { params: { id: string } }

export async function GET(request: NextRequest, { params }: Context) {
  const token = request.headers.get("x-token")
  const session = cookies().get("session")
  return NextResponse.json({ id: params.id, token, session })
}

export async function PUT(request: NextRequest, { params }: Context) {
  const body = await request.json()
  return NextResponse.json({ id: params.id, body })
}

export async function DELETE(request: NextRequest, { params }: Context) {
  return NextResponse.json({ id: params.id, deleted: true })
}
