import { api } from "encore.dev/api";

export const version = api({ expose: true, method: "GET", path: "/version" }, async (): Promise<void> => {});
