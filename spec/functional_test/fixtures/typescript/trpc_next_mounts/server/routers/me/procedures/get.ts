import { authedProcedure } from "../../../procedures";

export const get = authedProcedure.query(async ({ ctx }) => {
  return { session: ctx.session };
});
