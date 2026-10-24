import type { Next } from "koa";

type AuthenticationOptions = {
  optional?: boolean;
};

export default function auth(options: AuthenticationOptions = {}) {
  return async function authMiddleware(ctx, next: Next) {
    try {
      ctx.state.auth = await validateAuthentication(ctx, options);
    } catch (err) {
      if (options.optional) {
        ctx.state.auth = {};
      } else {
        throw err;
      }
    }
    return next();
  };
}

async function validateAuthentication(
  ctx,
  options: AuthenticationOptions
): Promise<{
  token: string;
  scope?: string[];
}> {
  const token = ctx.get("authorization");
  if (!token) {
    throw AuthenticationError("Authentication required");
  }
  return { token };
}
