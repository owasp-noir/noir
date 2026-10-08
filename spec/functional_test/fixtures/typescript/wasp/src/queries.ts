import type { GetTasks } from "wasp/server/operations";

export const getTasks: GetTasks<{ status?: string }, unknown[]> = async (args, context) => {
  const { status, limit } = args;
  return context.entities.Task.findMany({ where: { status }, take: limit });
};

export async function getHTTPStatus(_args, _context) {
  return { ok: true };
}
