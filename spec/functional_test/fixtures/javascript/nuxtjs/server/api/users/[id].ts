// Nuxt 3 API route - dynamic route with path parameter
export default defineEventHandler(async (event) => {
  const id = event.context.params.id
  
  return {
    user: { id }
  }
})
