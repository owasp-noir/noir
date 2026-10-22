// Same route name as apps/admin/server/routes/auth.ts, different handler:
// the public site reads its own session cookie.
export default defineEventHandler((event) => {
  const token = getCookie(event, 'site_session')

  return {
    authenticated: !!token
  }
})
