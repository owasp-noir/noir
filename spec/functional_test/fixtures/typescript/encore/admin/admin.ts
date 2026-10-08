import { api } from "encore.dev/api";

// Not exposed: callable only from other services.
export const stats = api({ method: "GET", path: "/admin/stats" }, async (): Promise<void> => {});
