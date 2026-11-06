import fastify from "fastify";
import { registerAll } from "./all";
import { getUserId } from "./ids";

const app = fastify();
await app.register(
  async (api: FastifyInstance) => {
    await registerAll(api);
  },
  { prefix: "/api" }
);
await app.register(
  async (admin: FastifyInstance) => {
    getUserId(admin);
  },
  { prefix: "/admin" }
);
