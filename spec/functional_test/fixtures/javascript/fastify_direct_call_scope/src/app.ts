import fastify from "fastify";
import { auditHook, usersRouter } from "./users";
import { hashPassword } from "./util";

const app = fastify();
await app.register(usersRouter, { prefix: "/users" });
await app.register(
  async (admin: FastifyInstance) => {
    auditHook(admin);
    hashPassword(admin);
  },
  { prefix: "/admin" }
);
