import gleam/http.{Delete, Get, Post}
import gleam/http/request
import gleam/list
import gleam/result
import wisp.{type Request, type Response}

pub fn collection(req: Request) -> Response {
  case req.method {
    Get -> list_users(req)
    Post -> create_user(req)
    _ -> wisp.method_not_allowed([Get, Post])
  }
}

pub fn show(req: Request, id: String) -> Response {
  case req.method {
    Get -> show_user(req, id)
    Delete -> delete_user(req, id)
    _ -> wisp.method_not_allowed([Get, Delete])
  }
}

fn list_users(req: Request) -> Response {
  let _query = wisp.get_query(req)
  wisp.ok()
}

fn create_user(req: Request) -> Response {
  use formdata <- wisp.require_form(req)

  let result = {
    use name <- result.try(list.key_find(formdata.values, "name"))
    use email <- result.try(list.key_find(formdata.values, "email"))
    Ok(name <> email)
  }

  case result {
    Ok(_) -> wisp.created()
    Error(_) -> wisp.bad_request()
  }
}

fn show_user(req: Request, id: String) -> Response {
  let _token = request.get_header(req, "x-api-token")
  wisp.ok()
}

fn delete_user(_req: Request, _id: String) -> Response {
  wisp.no_content()
}
