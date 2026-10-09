import * as HttpApiEndpoint from "@effect/platform/HttpApiEndpoint"
import * as HttpApiGroup from "@effect/platform/HttpApiGroup"
import { Schema } from "effect"

class NewOrder extends Schema.Class<NewOrder>("NewOrder")({
  sku: Schema.String,
  quantity: Schema.Number,
}) {}

export const OrdersGroup = HttpApiGroup.make("orders")
  .add(HttpApiEndpoint.post("place", "/orders").setPayload(NewOrder))
