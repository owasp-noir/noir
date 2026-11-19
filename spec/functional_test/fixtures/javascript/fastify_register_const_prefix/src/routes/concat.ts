import { FastifyInstance } from 'fastify';
export default async function (fastify: FastifyInstance) {
  fastify.get('/concat-leaf', async () => 'x');
}
