const userService = require('../services/userService')

class UserController {
  async list(req, res) {
    const { page, pageSize } = req.query
    res.json(await userService.list(page, pageSize))
  }

  async create(req, res) {
    const { email, password } = req.body
    res.status(201).json(await userService.create(email, password))
  }

  show = async (req, res) => {
    res.json(await userService.find(req.params.id))
  }
}

module.exports = UserController
