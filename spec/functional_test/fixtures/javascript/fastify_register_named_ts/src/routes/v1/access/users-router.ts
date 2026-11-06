export const registerAccessUsersRouter = async (server: FastifyInstance) => {
  server.route({
    method: "DELETE",
    url: "/access/users/:userId",
    handler: async () => ({})
  });
};
