// Nuxt 3 API route - DELETE with path parameter and headers
export default defineEventHandler(async (event) => {
  const id = event.context.params.id
  const authorization = getHeader(event, 'authorization')
  
  return {
    deleted: true,
    id
  }
})
