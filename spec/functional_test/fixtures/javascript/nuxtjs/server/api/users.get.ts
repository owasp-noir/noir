// Nuxt 3 API route - GET only endpoint with query parameters
export default defineEventHandler(async (event) => {
  const query = getQuery(event)
  const page = query.page
  const limit = query.limit
  const search = query.search

  return {
    users: [],
    page,
    limit
  }
})
