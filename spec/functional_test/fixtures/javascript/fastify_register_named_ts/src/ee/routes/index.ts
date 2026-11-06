import { registerLicenseRouter } from "./license-router";

export const registerEeRoutes = async (server: FastifyInstance) => {
  await server.register(registerLicenseRouter, { prefix: "/license" });
};
