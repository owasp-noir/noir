// The non-GET branch does the write and validates with a 400 from a nested
// `if`: that is not an early-exit method guard, so every method stays.
export default async function handler(req, res) {
  if (req.method !== 'GET') {
    const id = req.body.id
    if (!id) return res.status(400).json({ error: 'missing id' })
    await save(id)
    return res.status(201).end()
  }
  res.json(await list())
}
