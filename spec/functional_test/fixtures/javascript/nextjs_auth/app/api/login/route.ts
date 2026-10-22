import { NextRequest, NextResponse } from "next/server";
import { findUser } from "@/lib/users";

export async function POST(request: NextRequest) {
  const { email, password } = await request.json();
  const user = await findUser(email, password);
  if (!user) {
    return NextResponse.json({ message: "Invalid credentials" }, { status: 401 });
  }
  return NextResponse.json({ token: user.token });
}
