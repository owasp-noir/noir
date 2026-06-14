import { FastifyInstance } from 'fastify';

export default async function (app: FastifyInstance) {
  app.get('/:id', async (request) => ({ id: (request.params as any).id }));
  app.post('/', async (request) => {
    const { title } = request.body as any;
    return { title };
  });
}
