import fastify from "fastify";

import { registerRoutes } from "./routes";

const server = fastify();
await server.register(registerRoutes);
await server.listen({ port: 3000 });
