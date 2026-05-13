import { NextRequest, NextResponse } from "next/server"
import { cookies } from "next/headers"

type Context = { params: { id: string } }

export async function GET(request: NextRequest, { params }: Context) {
  const session = cookies().get("session")
  const order = await loadOrder(params.id, session)

  return NextResponse.json(formatOrder(order))
}

export const POST = async (request: NextRequest, { params }: Context) => {
  const body = await request.json()
  await serviceFactory().create(params.id, body)
  AuditLog.write("next:orders")

  return NextResponse.json({ ok: true })
}
