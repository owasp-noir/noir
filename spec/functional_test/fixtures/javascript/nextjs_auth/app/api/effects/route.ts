import { NextRequest, NextResponse } from "next/server";
import { validateCronRequest } from "../../../lib/guard";

// Each runs a write before the check.
export async function GET(request: NextRequest) {
  const r = await fetch(process.env.HOOK_URL!, { method: "POST" });
  validateCronRequest(request);
  return NextResponse.json({ ok: true });
}

export async function POST(request: NextRequest) {
  const n = await sql`DELETE FROM t`;
  validateCronRequest(request);
  return NextResponse.json({ n });
}

export async function PUT(request: NextRequest) {
  console.log("put", await request.text());
  validateCronRequest(request);
  return NextResponse.json({ ok: true });
}
