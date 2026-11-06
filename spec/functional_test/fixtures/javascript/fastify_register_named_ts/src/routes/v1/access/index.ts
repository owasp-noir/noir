import { registerAccessUsersRouter } from "./users-router";

export const registerAccessRouter = async (server: FastifyInstance) => {
  await registerAccessUsersRouter(server);
};
