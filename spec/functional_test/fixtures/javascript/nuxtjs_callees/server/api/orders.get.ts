import { defineEventHandler as h } from "h3"

export default h((event) => {
  const query = getQuery(event)
  const orders = listOrders(query.status)
  return sendOrders(serializeOrders(orders))
})
