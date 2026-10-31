import { NextRequest, NextResponse } from "next/server";
import { checkSession, validateCronRequest } from "../../../lib/guard";

// A write before the (throwing) check runs for every caller.
export async function GET(request: NextRequest) {
  await db.purgeAll();
  validateCronRequest(request);
  return NextResponse.json({ ok: true });
}

// The returned 401 is dropped: the write still runs.
export async function POST(request: NextRequest) {
  await checkSession();
  await db.write(await request.json());
  return NextResponse.json({ ok: true });
}

// The returned 401 is handed on.
export async function PUT(request: NextRequest) {
  const denied = await checkSession();
  if (denied) return denied;
  return NextResponse.json({ ok: true });
}

// A public value in the accepted list: a plan check, not a key check.
export async function DELETE(request: NextRequest) {
  const plan = request.headers.get("x-plan");
  if (![process.env.STRIPE_PUBLISHABLE_KEY, "free"].includes(`${plan}`)) {
    return NextResponse.json({ message: "unknown plan" }, { status: 403 });
  }
  return NextResponse.json({ ok: true });
}

// A key the browser is given is not a secret.
export async function PATCH(request: NextRequest) {
  if (request.headers.get("x-key") !== process.env.NEXT_PUBLIC_SITE_KEY) {
    return NextResponse.json({ message: "bad key" }, { status: 401 });
  }
  return NextResponse.json({ ok: true });
}
