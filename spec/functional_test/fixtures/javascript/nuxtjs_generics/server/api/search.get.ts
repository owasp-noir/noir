interface SearchQuery {
  q: string
}

export default defineEventHandler((event) => {
  const query = getQuery<SearchQuery>(event)
  return { results: [], q: query.q }
})
