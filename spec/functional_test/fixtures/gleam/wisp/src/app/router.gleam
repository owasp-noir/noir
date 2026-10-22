//// The main router. Wisp has no route table — routing is a `case`
//// over the split path.

import app/web/posts
import app/web/users
import gleam/http.{Get}
import wisp.{type Request, type Response}

pub fn handle_request(req: Request) -> Response {
  use req <- middleware(req)

  case wisp.path_segments(req) {
    // "//" below is a string pattern, not a comment.
    [] -> home(req)

    ["about"] | ["info"] -> about(req)

    // Delegates across modules; the verb lives in the handler.
    ["users"] -> users.collection(req)
    ["users", id] -> users.show(req, id)

    // A mount: posts.router/1 matches the same absolute paths itself.
    ["posts", ..] -> posts.router(req)

    ["search"] -> search(req)

    ["static", ..] -> wisp.serve_static(req, under: "/static", from: "priv")

    _ -> wisp.not_found()
  }
}

fn middleware(req: Request, handle: fn(Request) -> Response) -> Response {
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  handle(req)
}

fn home(req: Request) -> Response {
  use <- wisp.require_method(req, Get)
  wisp.ok()
}

fn about(req: Request) -> Response {
  use <- wisp.require_method(req, Get)
  wisp.ok()
}

fn search(req: Request) -> Response {
  use <- wisp.require_method(req, Get)
  let _query = wisp.get_query(req)
  wisp.ok()
}

fn normalize(input: String) -> String {
  case input {
    // A scheme-relative path is not a comment either.
    "//" <> _ -> "/"
    "/" <> _ -> input
    _ -> "/"
  }
}
