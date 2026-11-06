import { registerAccessRouter } from "./access";
import { registerAdminRouter } from "./admin-router";
import { registerReadRouter, registerWriteRouter } from "./split-router";

export const registerV1Routes = async (server: FastifyInstance) => {
  await server.register(registerAdminRouter, { prefix: "/admin" });
  await server.register(registerReadRouter, { prefix: "/read" });
  await server.register(registerWriteRouter, { prefix: "/write" });
  await server.register(
    async (pkiRouter) => {
      await registerAccessRouter(pkiRouter);
    },
    { prefix: "/pki" }
  );
};
