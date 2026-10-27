exports.setReturnToFromReferer = function setReturnToFromReferer (req) {
  req.session.returnTo = req.get('referer')
}
