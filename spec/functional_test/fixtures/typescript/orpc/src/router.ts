import type { IncomingHttpHeaders } from 'node:http';
import { ORPCError, os } from '@orpc/server';
import * as z from 'zod';

const PlanetSchema = z.object({
  id: z.number().int().min(1),
  name: z.string(),
  description: z.string().optional(),
});

export const listPlanet = os
  .route(/* spec */ { method: 'GET', path: '/planets' })
  .input(
    z.object({
      limit: z.number().int().min(1).max(100).optional(),
      cursor: z.number().int().min(0).default(0),
    }),
  )
  .output(z.array(PlanetSchema))
  .handler(async ({ input }) => {
    return [];
  });

export const getPlanet = os
  .route({ method: 'GET', path: '/planets/{id}' })
  .input(z.object({ id: z.number() }))
  .handler(async ({ input }) => {
    throw new ORPCError('NOT_FOUND', { message: `planet ${input.id}` });
  });

export const createPlanet = os
  .$context<{ headers: IncomingHttpHeaders }>()
  .input(PlanetSchema.omit({ id: true }))
  .route({ path: '/planets' })
  .handler(async ({ input, context }) => {
    return { id: 1, ...input };
  });

// `{+path}` matches the rest of the URL.
export const getFile = os
  .route({ method: 'GET', path: '/files/{+path}' })
  .handler(async () => 'file');

// No `.route()`: reachable only through the RPC protocol, not as REST.
export const ping = os.handler(async () => 'pong');

const deletePlanet = os
  .route({ method: 'DELETE', path: '/{id}' })
  .input(z.object({ id: z.number() }))
  .handler(async () => ({ ok: true }));

export const router = {
  planet: {
    list: listPlanet,
    find: getPlanet,
    create: createPlanet,
  },
  admin: os.prefix('/admin/planets').router({
    remove: deletePlanet,
  }),
  ping,
};
