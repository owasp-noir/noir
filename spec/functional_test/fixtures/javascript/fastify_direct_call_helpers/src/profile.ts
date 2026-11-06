export const profileRouter = async (s: FastifyInstance) => {
  s.get("/me", async () => ({}));
};
