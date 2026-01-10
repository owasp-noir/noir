// Nuxt 3 server route - custom route without /api prefix
export default defineEventHandler((event) => {
  const token = getCookie(event, 'session')
  
  return {
    authenticated: !!token
  }
})
