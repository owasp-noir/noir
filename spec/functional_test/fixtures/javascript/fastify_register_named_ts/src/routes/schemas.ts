export const buildSchemas = (server: FastifyInstance) => {
  server.addSchema({ $id: "id", type: "string" });
};
