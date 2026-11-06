import { localChild } from "./child";

const registerLocal = async (s: FastifyInstance) => {
  s.get("/local", async () => ({}));
  await s.register(localChild, { prefix: "/lc" });
};

export const registerAll = async (server: FastifyInstance) => {
  await registerLocal(server);
};
