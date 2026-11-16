const accountService = require('../services/accountService')

class BaseController {
  ping(req, res) {
    res.send('pong')
  }

  login(req, res) {
    res.status(501).end()
  }
}

class AccountController extends BaseController {
  login = async (req, res) => {
    const { username, password } = req.body
    res.json(await accountService.login(username, password))
  }
}

module.exports = { AccountController }
