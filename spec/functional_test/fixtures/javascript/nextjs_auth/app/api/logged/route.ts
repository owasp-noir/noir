import { auth } from "@/lib/auth";
import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const session = await auth();

  if (!session?.user) {
    logger.warn("Returning 401", {
      path: new URL(request.url).pathname,
      reason:
        session === null || session === undefined
          ? "no_session"
          : "session_without_user",
    });

    return NextResponse.json(
      { error: "Unauthorized" },
      { status: 401 },
    );
  }

  return NextResponse.json([]);
}

export async function POST(request: Request) {
  const session = await auth();

  if (!session?.user) {
    return NextResponse.json([]);
  } else {
    logger.info("Signed in", {
      path: new URL(request.url).pathname,
      user: session.user.id,
      method: request.method,
      agent: request.headers.get("user-agent"),
    });

    return NextResponse.json({ error: "Wrong state" }, { status: 401 });
  }
}
