import { FastifyInstance } from 'fastify';

export default async function (app: FastifyInstance) {
  app.get('/:id', async (request) => request.params);
}
