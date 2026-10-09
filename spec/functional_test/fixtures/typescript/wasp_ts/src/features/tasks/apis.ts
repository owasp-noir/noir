import type { ExportTasks, UploadTasks } from "wasp/server/api";

export const exportTasks: ExportTasks = async (req, res, context) => {
  const format = req.query.format;
  res.json(await context.entities.Task.findMany({ take: Number(req.query.limit) }));
};

export const uploadTasks: UploadTasks = async (req, res) => {
  const { tasks } = req.body;
  res.json({ count: tasks.length });
};

export const tasksMiddleware = (config) => config;
