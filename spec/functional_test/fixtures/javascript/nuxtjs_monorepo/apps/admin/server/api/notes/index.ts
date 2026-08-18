// See ../notes.ts — same resolved route, a second input.
export default defineEventHandler((event) => {
  const { cursor } = getQuery(event)

  return { notes: [], cursor }
})
