export const registerLicenseRouter = async (server: FastifyInstance) => {
  server.route({
    method: "GET",
    url: "/plan",
    handler: async () => ({})
  });
};
