export default defineEventHandler((event) => {
  const slug = getRouterParam(event, "slug")
  const { tag } = getQuery(event)
  return { slug, tag }
})
