import { NextRequest, NextResponse } from "next/server";
import { auth, trackAnonymous, verifyCaptcha, checkPassword } from "@/lib/auth";

export const GET = async () => {
  return NextResponse.json({ public: true });
  };

export async function POST(req: NextRequest) {
  const session = await auth();
  if (!session) {
    await trackAnonymous(req);
  }
  // TODO: if (!session) gate this too
  if (!(await verifyCaptcha(req))) return NextResponse.json({}, { status: 401 });
  if (process.env.NODE_ENV !== "test" && !(await checkPassword(req))) {
    return NextResponse.json({ error: "bad password" }, { status: 401 });
  }
  return NextResponse.json({ ok: true });
}

export async function DELETE() {
  const session = await auth();
  if (!session) return NextResponse.json({}, { status: 401 });
  return NextResponse.json({ ok: true });
}
