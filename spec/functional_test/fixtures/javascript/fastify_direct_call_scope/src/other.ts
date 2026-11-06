export const otherRouter = async (s: FastifyInstance) => {
  s.route({ method: "GET", url: "/x", handler: async () => ({}) });
};
