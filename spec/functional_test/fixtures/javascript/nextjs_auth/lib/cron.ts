import type { NextRequest } from "next/server";

async function handler(request: NextRequest) {
  const authHeader = request.headers.get("authorization");
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response("Unauthorized", { status: 401 });
  }
  return new Response("ok");
}

export async function GET(request: NextRequest) {
  return await handler(request);
}

// A template that holds a public value is no secret check.
export async function POST(request: NextRequest) {
  if (request.headers.get("x-site") !== `site-${process.env.NEXT_PUBLIC_SITE_KEY}`) {
    return new Response("Unauthorized", { status: 401 });
  }
  return new Response("ok");
}
