import { registerEeRoutes } from "@app/ee/routes";
import { registerV1Routes } from "./v1";
import { buildSchemas } from "./schemas";

export const registerRoutes = async (server: FastifyInstance) => {
  buildSchemas(server);

  server.route({
    method: "GET",
    url: "/api/status",
    handler: async () => ({ ok: true })
  });

  await server.register(
    async (v1Server: FastifyInstance) => {
      // 버전 1 API (non-ASCII text before the nested registers)
      v1Server.log.info("버전 1 — ready");
      await v1Server.register(registerEeRoutes);
      await v1Server.register(registerV1Routes);
    },
    { prefix: "/api/v1" }
  );

  await server.register(
    async (v2Server) => {
      await v2Server.register(registerV1Routes, { prefix: "/legacy" });
    },
    { prefix: "/api/v2" }
  );
};
