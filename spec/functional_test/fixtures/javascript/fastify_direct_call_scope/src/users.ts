import { profileRouter } from "./profile";

export const auditHook = (app: FastifyInstance) => {
  app.addHook("onRequest", async () => {});
};

export const usersRouter = async (server: FastifyInstance) => {
  await server.register(profileRouter, { prefix: "/profile" });
};
