const orderService = require('../services/orders')

exports.show = async (request, reply) => {
  const { expand } = request.query
  return orderService.find(request.params.orderId, expand)
}

exports.create = async (request, reply) => {
  const { sku, quantity } = request.body
  reply.code(201)
  return orderService.create(sku, quantity)
}
