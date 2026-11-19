import { NextResponse } from "next/server";
import { auth } from "./session";

function withMiddleware(handler: any, middleware?: any, scope?: string) {
  return async (req: Request) => {
    let enhanced = req;
    if (middleware) {
      const result = await middleware(req);
      if (result instanceof Response) return result;
      enhanced = result;
    }
    return handler(enhanced);
  };
}

async function authMiddleware(req: Request) {
  const session = await auth(req.headers);
  if (!session?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  return req;
}

async function accountMiddleware(req: Request) {
  const authReq = await authMiddleware(req);
  if (authReq instanceof Response) return authReq;

  return authReq;
}

export function withError(scope: string, handler: any): any;
export function withError(handler: any): any;
export function withError(scopeOrHandler: any, handler?: any): any {
  if (typeof scopeOrHandler === "string") {
    return withMiddleware(handler, undefined, scopeOrHandler);
  }
  return withMiddleware(scopeOrHandler, undefined);
}

export function withAuth(scope: string, handler: any): any;
export function withAuth(handler: any): any;
export function withAuth(scopeOrHandler: any, handler?: any): any {
  if (typeof scopeOrHandler === "string") {
    return withMiddleware(handler, authMiddleware, scopeOrHandler);
  }
  return withMiddleware(scopeOrHandler, authMiddleware);
}

export function withAccount(scope: string, handler: any): any {
  return withMiddleware(handler, accountMiddleware, scope);
}

export function withOptional(handler: any, options: any = {}) {
  if (options.public) {
    return withMiddleware(handler);
  }
  return withMiddleware(handler, authMiddleware);
}

function withRunner(handler: any, middleware?: any) {
  return async (req: Request) => {
    await middleware(req);
    return handler(req);
  };
}

export function withDropped(handler: any) {
  return withRunner(handler, authMiddleware);
}
