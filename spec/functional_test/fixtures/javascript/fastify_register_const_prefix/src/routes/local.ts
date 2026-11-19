import { FastifyInstance } from 'fastify';
export default async function (fastify: FastifyInstance) {
  fastify.get('/local-leaf', async () => 'x');
}
