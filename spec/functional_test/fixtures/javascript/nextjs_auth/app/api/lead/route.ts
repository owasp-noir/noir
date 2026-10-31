import { NextRequest, NextResponse } from "next/server";
import { checkSession, validateCronRequest } from "../../../lib/guard";
import { GET as cronHandler } from "../../../lib/cron";

// An awaited read and a log line before the check run nothing a refused
// caller could use.
export async function GET(request: NextRequest) {
  const db = await getDb();
  console.log("lead", request.url);
  validateCronRequest(request);
  return NextResponse.json(await db.find());
}

// An awaited write before the check already ran.
export async function POST(request: NextRequest) {
  const row = await db.insertRow(await request.json());
  validateCronRequest(request);
  return NextResponse.json(row);
}

// The handler a wrapper is handed, from another module.
export const PUT = withResponder(cronHandler);

export async function DELETE() {
  return await checkSession();
}
