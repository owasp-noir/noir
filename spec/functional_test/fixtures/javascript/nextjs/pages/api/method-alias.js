// `method` destructured from the request, compared by bare name.
export default function handler(req, res) {
  const { method, query } = req
  if (method === "GET") {
    res.json({ query })
  } else if (method === "PUT") {
    res.json({})
  }
}
