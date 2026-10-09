import {
  action,
  api as waspApi,
  apiNamespace,
  crud,
  page,
  query,
  route,
  type Spec,
} from "@wasp.sh/spec";

import { createTask, updateTask as renameTask } from "./actions" with { type: "ref" };
import getOldestTask from "./getOldestTask" with { type: "ref" };
import { getTasks } from "./queries" with { type: "ref" };
import { exportTasks, tasksMiddleware, uploadTasks } from "./apis" with { type: "ref" };
import { TaskPage } from "./TaskPage" with { type: "ref" };

const taskPage = page(TaskPage, { authRequired: true });

export const tasksSpec: Spec = [
  route("TaskRoute", "/tasks/:taskId", taskPage),
  // route("OldRoute", "/old", page(TaskPage)),
  query(getTasks, { entities: ["Task"] }),
  query(getOldestTask, { entities: ["Task"], auth: false }),
  action(createTask, { entities: ["Task"] }),
  action(renameTask),
  apiNamespace("/api/tasks", { middlewareConfigFn: tasksMiddleware }),
  waspApi("GET", "/api/tasks/export", exportTasks, { auth: false }),
  waspApi("POST", "/api/tasks/:listId/upload", uploadTasks),
  crud("tasks", "Task", {
    get: {},
    update: { isPublic: true },
  }),
];
