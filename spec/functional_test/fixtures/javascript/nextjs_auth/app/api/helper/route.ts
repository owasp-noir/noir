import { NextRequest, NextResponse } from "next/server";
import { getServerSession } from "next-auth";
import { rejectSignedIn, validateCronRequest } from "../../../lib/guard";

async function authMiddleware() {
  const session = await getServerSession();
  if (!session?.user?.id) {
    throw new HttpError({ statusCode: 401, message: "Not authenticated" });
  }
  return session.user;
}

export async function GET() {
  const user = await authMiddleware();
  return NextResponse.json({ id: user.id });
}

export async function POST(request: NextRequest) {
  if (request.headers.get("x-preview")) {
    await authMiddleware();
  }
  return NextResponse.json({ ok: true });
}

export async function PUT(request: NextRequest) {
  validateCronRequest(request);
  return NextResponse.json({ ok: true });
}

export async function DELETE() {
  const session = await getServerSession();
  rejectSignedIn(session);
  return NextResponse.json({ ok: true });
}
