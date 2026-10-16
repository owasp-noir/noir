import { App } from "fresh";

export const app = new App();

app.get("/real-app", () => new Response("ok"));

app.fsRoutes();
