import { HttpApi, HttpApiEndpoint, HttpApiGroup, HttpApiSchema } from "@effect/platform"
import { Schema } from "effect"

class User extends Schema.Class<User>("User")({
  id: Schema.Number,
  name: Schema.String,
}) {}

const idParam = HttpApiSchema.param("id", Schema.NumberFromString)

const CreateUser = Schema.Struct({
  name: Schema.String,
  email: Schema.String,
})

export class UsersGroup extends HttpApiGroup.make("users")
  .add(HttpApiEndpoint.get("findById", "/users/:id").addSuccess(User))
  .add(HttpApiEndpoint.post("create", "/users").setPayload(CreateUser).addSuccess(User))
  .add(
    HttpApiEndpoint.get("search", "/users/search")
      .setUrlParams(Schema.Struct({ q: Schema.String, page: Schema.optional(Schema.NumberFromString) }))
      .addSuccess(Schema.Array(User))
  )
  .add(HttpApiEndpoint.del("remove")`/users/${idParam}`)
  .add(
    HttpApiEndpoint.patch("update", "/users/:id")
      .setHeaders(Schema.Struct({ "x-api-key": Schema.String }))
      .setPayload(Schema.Struct({ name: Schema.optional(Schema.String) }))
  )
{}

const HealthGroup = HttpApiGroup.make("health")
  .add(HttpApiEndpoint.get("check", "/health"))
  .prefix("/system")

const AdminGroup = HttpApiGroup.make("admin").add(HttpApiEndpoint.get("stats", "/stats"))

export class MyApi extends HttpApi.make("MyApi")
  .add(UsersGroup)
  .add(HealthGroup)
  .add(AdminGroup.prefix("/admin"))
{}
