// Same route name as apps/site/server/routes/auth.ts, different handler:
// the admin app reads its own session cookie.
export default defineEventHandler((event) => {
  const token = getCookie(event, 'admin_session')

  return {
    authenticated: !!token
  }
})
