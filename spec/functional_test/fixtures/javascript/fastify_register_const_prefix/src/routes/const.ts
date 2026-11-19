import { FastifyInstance } from 'fastify';
export async function constRoutes(fastify: FastifyInstance) {
  fastify.get('/const-leaf', async () => 'x');
}
