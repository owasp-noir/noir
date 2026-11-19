import { FastifyInstance } from 'fastify';
export default async function (fastify: FastifyInstance) {
  fastify.get('/literal-leaf', async () => 'x');
}
