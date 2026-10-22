import { db } from "../../db";

export async function reserveHandler(opts: { ctx: { session: { userId: string } } }) {
  return db.reservation.create({ data: { userId: opts.ctx.session.userId } });
}
