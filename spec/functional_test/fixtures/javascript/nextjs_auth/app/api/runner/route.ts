import { NextResponse } from "next/server";
import { withAccount, withAuth, withDropped, withError, withOptional } from "../../../lib/middleware";

export const GET = withAuth("items", async (request) => {
  return NextResponse.json([]);
});

export const POST = withError("items", async (request) => {
  return NextResponse.json([]);
});

export const PUT = withAccount("items", async (request) => {
  return NextResponse.json([]);
});

export const PATCH = withOptional(async (request) => NextResponse.json([]), { public: true });

export const DELETE = withDropped(async (request) => NextResponse.json([]));
