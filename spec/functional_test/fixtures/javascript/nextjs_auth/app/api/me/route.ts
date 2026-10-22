import { NextResponse } from "next/server";
import { getServerSession } from "next-auth";

async function getHandler() {
  const session = await getServerSession();
  if (!session?.user) {
    return NextResponse.json({ message: "Unauthorized" }, { status: 401 });
  }
  return NextResponse.json(session.user);
}

export const GET = getHandler;
