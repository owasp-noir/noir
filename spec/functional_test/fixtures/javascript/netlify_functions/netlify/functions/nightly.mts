import type { Config } from "@netlify/functions";

// Scheduled: runs on a cron, not reachable over HTTP.
export default async () => {
  await fetch("https://example.com/rebuild", { method: "POST" });
};

export const config: Config = {
  schedule: "@daily",
};
