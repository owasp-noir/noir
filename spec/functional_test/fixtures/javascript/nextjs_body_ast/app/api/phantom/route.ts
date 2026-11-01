import { NextRequest, NextResponse } from "next/server";

// a verb named inside a string is not an export
const sample = 'export function DELETE() {}';
const other = `export const PUT = 1`;

export async function GET(request: NextRequest) {
  return NextResponse.json({ sample, other, q: request.nextUrl.searchParams.get("q") });
}
