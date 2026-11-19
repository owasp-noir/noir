import { NextResponse } from "next/server";
import { withAccount, withAuth, withError } from "../../../lib/middleware";

export const GET = withAuth("items", async (request) => {
  return NextResponse.json([]);
});

export const POST = withError("items", async (request) => {
  return NextResponse.json([]);
});

export const PUT = withAccount("items", async (request) => {
  return NextResponse.json([]);
});
