import { HttpError } from "wasp/server";
import type { CreateTask } from "wasp/server/operations";

type CreateTaskArgs = { description: string; dueDate?: string };

export const createTask: CreateTask<CreateTaskArgs, void> = async (args, context) => {
  if (!context.user) {
    throw new HttpError(401);
  }
  await context.entities.Task.create({
    data: { description: args.description, dueDate: args.dueDate, user: { connect: { id: context.user.id } } },
  });
};

export const createTaskCrud = async ({ title, priority }: { title: string; priority: number }, context) => {
  return context.entities.Task.create({ data: { title, priority } });
};
