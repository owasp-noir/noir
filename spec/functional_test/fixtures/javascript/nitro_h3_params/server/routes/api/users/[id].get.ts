export default defineEventHandler(async (event) => {
  const { fields } = getQuery(event)
  return { id: getRouterParam(event, 'id'), fields }
})
