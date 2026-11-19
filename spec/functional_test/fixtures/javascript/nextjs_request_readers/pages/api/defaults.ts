export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).end();
  const { limit = "10", cursor } = req.query;
  const { email, name: displayName } = req.body;
  res.json({ limit, cursor, email, displayName });
}
