import * as trpc from '@trpc/server';

type Context = {
  userId?: string;
};

export function createRouter() {
  return trpc.router<Context>();
}
