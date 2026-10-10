// Nitro route - DELETE with path parameter and headers
export default defineEventHandler(async (event) => {
  const id = event.context.params.id
  const authorization = getHeader(event, /* bearer */ 'authorization')

  return {
    deleted: true,
    id
  }
})
