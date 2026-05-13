const wrap = defineEventHandler

export default wrap((event) => {
  const token = getCookie(event, "session")
  return authorizeUser(token)
})
