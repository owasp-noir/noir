import { publicProcedure } from "../../../procedures";

export const get = publicProcedure.query(async () => {
  return { status: "ok" };
});
