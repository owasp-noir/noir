import { api, Header, Query } from "encore.dev/api";

interface SearchParams {
  q: Query<string>;
  limit?: Query<number>;
  token: Header<"X-Token">;
}

interface Response {
  message: string;
}

export const get = api(
  { expose: true, method: "GET", path: "/hello/:name" },
  async ({ name }: { name: string }): Promise<Response> => {
    return { message: `Hello ${name}!` };
  },
);

export const search = api<SearchParams, Response>(
  { expose: true, method: "GET", path: "/search" },
  async (p) => ({ message: p.q }),
);

// No path: defaults to /greeter.create, and no method: POST.
export const create = api(
  { expose: true, auth: true },
  async (p: { title: string; body: string }): Promise<Response> => ({ message: p.title }),
);

export const update = api(
  { expose: true, method: ["PUT", "PATCH"], path: "/posts/:id" },
  async (p: { id: number; title: string }): Promise<Response> => ({ message: p.title }),
);

export const hook = api.raw(
  { expose: true, method: "*", path: "/hooks/*rest" },
  async (req, resp) => {
    resp.end();
  },
);

export const chat = api.streamInOut<{ room: Query<string> }, string, string>(
  { expose: true, path: "/chat" },
  async (handshake, stream) => {},
);

export const assets = api.static({ expose: true, path: "/static/*path", dir: "./assets" });

export const fallback = api.static({ expose: true, path: "/!path", dir: "./public" });

// export const old = api({ expose: true, method: "GET", path: "/old" }, async () => {});
