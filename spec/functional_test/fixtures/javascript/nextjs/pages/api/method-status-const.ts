import { StatusCodes } from 'http-status-codes'

// A named 405 constant, and `method` destructured next to a nested pattern.
export default async function handler(req, res) {
  const { query: { id }, method } = req
  if (method !== 'DELETE') {
    return res.status(StatusCodes.METHOD_NOT_ALLOWED).end()
  }
  res.json({ id })
}
