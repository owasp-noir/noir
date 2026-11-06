export const profileRouter = async (s: FastifyInstance) => {
  s.route({ method: "GET", url: "/me", handler: async () => ({}) });
};
