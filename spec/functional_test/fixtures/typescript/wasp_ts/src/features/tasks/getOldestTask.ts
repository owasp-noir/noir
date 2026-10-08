export default async function getOldestTask(args, context) {
  return context.entities.Task.findFirst({ where: { listId: args.listId }, orderBy: { createdAt: "asc" } });
}
