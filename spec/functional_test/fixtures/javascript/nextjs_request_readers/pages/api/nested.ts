export default function handler(req, res) {
  const {
    query: { page, sort },
    method,
  } = req;
  if (method !== "GET") return res.status(405).end();
  res.json({ page, sort });
}
