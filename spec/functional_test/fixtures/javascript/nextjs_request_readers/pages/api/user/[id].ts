import type { NextApiRequest, NextApiResponse } from "next";

// Shape of the official `examples/api-routes-rest` handler.
export default function userHandler(req: NextApiRequest, res: NextApiResponse) {
  const { query, body, method } = req;
  const id = parseInt(query.id as string, 10);
  const expand = query.expand;
  switch (method) {
    case "GET":
      res.status(200).json({ id, expand });
      break;
    case "PATCH": // Shares the update read by falling through.
    case "PUT":
      res.status(200).json({ id, name: body.name });
      break;
    default:
      res.setHeader("Allow", ["GET", "PATCH", "PUT"]);
      res.status(405).end(`Method ${method} Not Allowed`);
  }
}
