import { profileRouter } from "./profile";

export const getUserId = (server: FastifyInstance) => server.user;

export const usersRouter = async (server: FastifyInstance) => {
  await server.register(profileRouter, { prefix: "/profile" });
};
