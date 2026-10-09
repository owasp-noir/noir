import type { CreateTask, UpdateTask } from "wasp/server/operations";

export const createTask: CreateTask<{ description: string }, void> = async ({ description, isDone = false }, context) => {
  await context.entities.Task.create({ data: { description, isDone } });
};

export const updateTask = (async (args, context) => {
  return context.entities.Task.update({ where: { id: args.id }, data: { title: args.title } });
}) satisfies UpdateTask;
