import { App } from "fresh";

export const app = new App();

app.get("/harness", () => new Response("ok"));
