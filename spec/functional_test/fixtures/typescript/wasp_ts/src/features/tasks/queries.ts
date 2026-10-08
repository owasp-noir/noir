import type { GetTasks } from "wasp/server/operations";

export const getTasks: GetTasks<void, unknown[]> = (_args, context) => {
  return context.entities.Task.findMany();
};
