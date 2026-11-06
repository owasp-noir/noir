export const registerAdminRouter = async (server: FastifyInstance) => {
  server.route({
    method: "GET",
    url: "/config",
    handler: async () => ({})
  });
};
