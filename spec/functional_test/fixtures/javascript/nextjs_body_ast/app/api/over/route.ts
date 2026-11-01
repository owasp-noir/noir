import { NextRequest, NextResponse } from "next/server";
import { lookup } from "@/lib/lookup";

export function GET(request: NextRequest): { a: 1 };
export function GET(request: NextRequest, extra: string): { b: 2 };
export function GET(request: NextRequest, extra?: string): { a: 1 } | { b: 2 } {
  const filter = request.nextUrl.searchParams.get("filter");
  return NextResponse.json(lookup(filter));
}
