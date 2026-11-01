import { NextRequest, NextResponse } from "next/server";
import { renderCard } from "@/lib/card";

export async function GET(request: NextRequest) {
  const view = <div className={`a ${ { b: 1 }.b }`}>{"}"}</div>;
  function inner() {
    return { deep: { deeper: [1, { three: 3 }] } };
  }
  const q = request.nextUrl.searchParams.get("q");
  return NextResponse.json(await renderCard(view, inner(), q));
}
