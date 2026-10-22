//// A sub-router. Note it matches the *absolute* path, not a remainder,
//// which is why the parent's `["posts", ..]` arm must not also emit a
//// wildcard route.

import gleam/dynamic/decode
import gleam/http
import wisp.{type Request, type Response}

pub fn router(req: Request) -> Response {
  // Subject order is path-then-method here.
  case wisp.path_segments(req), req.method {
    ["posts"], http.Get -> index(req)
    ["posts"], http.Post -> create(req)
    ["posts", id], http.Get -> show(req, id)
    ["posts", id], http.Delete -> delete(req, id)
    ["posts", post_id, "comments"], http.Get -> comments(req, post_id)
    _, _ -> wisp.not_found()
  }
}

fn index(req: Request) -> Response {
  let _query = wisp.get_query(req)
  wisp.ok()
}

fn create(req: Request) -> Response {
  use json <- wisp.require_json(req)

  case decode.run(json, post_decoder()) {
    Ok(_) -> wisp.created()
    Error(_) -> wisp.unprocessable_entity()
  }
}

fn post_decoder() -> decode.Decoder(#(String, String)) {
  use title <- decode.field("title", decode.string)
  use content <- decode.field("content", decode.string)
  decode.success(#(title, content))
}

fn show(_req: Request, _id: String) -> Response {
  wisp.ok()
}

fn delete(_req: Request, _id: String) -> Response {
  wisp.no_content()
}

fn comments(_req: Request, _post_id: String) -> Response {
  wisp.ok()
}
