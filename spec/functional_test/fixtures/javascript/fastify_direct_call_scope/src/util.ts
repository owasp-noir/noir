import { otherRouter } from "./other";

export const hashPassword = (pw: string) => {
  return bcrypt.hash(pw, 10);
};

export const utilRouter = async (s: FastifyInstance) => {
  await s.register(otherRouter, { prefix: "/o" });
};
