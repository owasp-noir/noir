export const localChild = async (s: FastifyInstance) => {
  s.get("/kid", async () => ({}));
};
