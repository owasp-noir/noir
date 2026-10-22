import { NextResponse } from "next/server";
import { auth } from "@/lib/auth";

async function getHandler() {
  const session = await auth();
  if (!session) {
    return NextResponse.json(
      {
        error: "Unauthorized",
        message: "Sign in to see your notifications",
      },
      { status: 401 }
    );
  }
  return NextResponse.json({ ok: true });
}

export const GET = withErrors(getHandler);
