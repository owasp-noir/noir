import { headers, cookies } from "next/headers";
import { NextRequest, NextResponse } from "next/server";

export async function POST(request: NextRequest) {
  const headersList = await headers();
  const signature = headersList.get("stripe-signature");
  const idem = (await headers()).get("idempotency-key");
  const theme = (await cookies()).get("theme");
  const session = request.cookies.get("session")?.value;
  const sp = request.nextUrl.searchParams;
  const dryRun = sp.get("dryRun");
  const form = await request.formData();
  const tags = form.getAll("tags");
  return NextResponse.json({ signature, idem, theme, session, dryRun, tags });
}
