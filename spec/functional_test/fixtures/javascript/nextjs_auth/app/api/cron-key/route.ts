import { NextRequest, NextResponse } from "next/server";

export async function GET(request: NextRequest) {
  const apiKey = request.headers.get("authorization") || request.nextUrl.searchParams.get("apiKey");
  if (![process.env.CRON_API_KEY, `Bearer ${process.env.CRON_SECRET}`].includes(`${apiKey}`)) {
    return NextResponse.json({ message: "Forbidden" }, { status: 403 });
  }
  return NextResponse.json({ ok: true });
}

export async function POST(request: NextRequest) {
  const apiKey = request.headers.get("authorization");
  // Refuses the caller who HAS the key: the wrong polarity.
  if ([process.env.CRON_API_KEY].includes(`${apiKey}`)) {
    return NextResponse.json({ message: "Forbidden" }, { status: 403 });
  }
  return NextResponse.json({ ok: true });
}
