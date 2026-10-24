export function rateLimiter() {
  return async function rateLimiterMiddleware(ctx, next) {
    return next();
  };
}
