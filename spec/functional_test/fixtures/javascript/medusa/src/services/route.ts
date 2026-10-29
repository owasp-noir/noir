export const GET = async (req, res) => {
  res.json({ notAnApi: req.query.nope })
}
