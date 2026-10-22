// Nitro api/ route - served under /api, GET only
export default defineEventHandler((event) => {
  const verbose = getQuery(event).verbose
  return { ok: true, verbose }
})
