import { NextRequest, NextResponse } from "next/server";
import { render } from "@/lib/render";

export async function GET(request: NextRequest) {
  const label = `limit=${ { a: 1 }.a } ${ "}" }`;
  const closing = /}{/.test(label) ? 1 : 0;
  const token = request.headers.get("x-tmpl-token");
  return NextResponse.json(await render(label, closing, token));
}

export async function DELETE(request: NextRequest) {
  const id = request.nextUrl.searchParams.get("id");
  return NextResponse.json(await render("x", 0, id));
}
