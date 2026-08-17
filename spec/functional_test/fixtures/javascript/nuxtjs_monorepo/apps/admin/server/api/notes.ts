// Nitro resolves `notes.ts` and `notes/index.ts` to the same route, so both
// files' inputs belong to one endpoint.
export default defineEventHandler((event) => {
  const query = getQuery(event)
  const sort = query.sort

  return { notes: [], sort }
})
