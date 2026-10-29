export function withAuth(router) {
  return (req, res, next) => (req.user ? router(req, res, next) : res.status(401).end())
}
