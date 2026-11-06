export const registerReadRouter = async (server: FastifyInstance) => {
  server.route({
    method: "GET",
    url: "/items",
    handler: async () => []
  });
};

export const registerWriteRouter = async (server: FastifyInstance) => {
  server.route({
    method: "POST",
    url: "/items",
    handler: async () => ({})
  });
};
