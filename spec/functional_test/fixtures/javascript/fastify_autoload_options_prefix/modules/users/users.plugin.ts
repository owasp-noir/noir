import { FastifyInstance } from 'fastify';
import usersRoutes from './users.routes';

export default async function (app: FastifyInstance) {
  await app.register(usersRoutes);
}
