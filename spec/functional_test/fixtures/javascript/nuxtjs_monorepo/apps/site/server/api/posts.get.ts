// A route only the public site serves, so it must stay on its own.
export default defineEventHandler((event) => {
  const query = getQuery(event)
  const tag = query.tag

  return { posts: [], tag }
})
