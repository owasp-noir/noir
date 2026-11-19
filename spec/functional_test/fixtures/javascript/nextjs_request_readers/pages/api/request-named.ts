import type { NextApiRequest, NextApiResponse } from "next";
export default async function handler(request: NextApiRequest, response: NextApiResponse) {
  if (request.method !== "POST") return response.status(405).end();
  const { q } = request.query;
  const title = request.body.title;
  const token = request.headers["x-token"];
  const sid = request.cookies.sid;
  response.json({ q, title, token, sid });
}
