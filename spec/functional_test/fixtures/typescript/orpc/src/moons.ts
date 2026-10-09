// Built on a base procedure from a local module: no oRPC import here.
import * as z from 'zod';
import { pub } from './base';

const listMoons = pub
  .route({ method: 'GET', path: '/moons' })
  .input(z.object({ planetId: z.number() }))
  .handler(async () => []);

const moonRouter = { list: listMoons };

const getMoon = pub
  .$context<{ db: Map<string, Array<number>> }>()
  .route({ method: 'GET', path: '/moons/{id}' })
  .handler(async () => null);

export const moons = {
  v1: pub.prefix('/v1').router(moonRouter),
  v2: pub.prefix('/v2').router({ ...moonRouter, get: getMoon }),
};

// A Hapi/Fastify-style route config carries a handler and is not oRPC.
server.route({ method: 'GET', path: '/not-orpc', handler: () => 1 });
