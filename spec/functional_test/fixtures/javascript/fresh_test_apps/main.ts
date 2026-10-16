import { App } from "fresh";

export const app = new App();

app.get("/ping", () => new Response("pong"));
