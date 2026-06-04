// poem: verb-less `.at(path, handler)`, single-arg request header reads,
// response-builder `.header(name, value)` (must NOT be a request param),
// and `#[cfg(test)]` gating.
use poem::http::header;
use poem::{get, handler, Request, Response, Route};

#[handler]
fn index() {}

#[handler]
fn hello() {}

#[handler]
fn read_header(req: &Request) -> String {
    req.header("X-Request-Id").unwrap_or_default().to_string()
}

#[handler]
fn redirect() -> Response {
    // Two-arg response-builder set: NOT a request header param.
    Response::builder().header(header::LOCATION, "/signin").finish()
}

fn app() -> Route {
    Route::new()
        .at("/", index)
        .at("/hello", get(hello))
        .at("/whoami", get(read_header))
        .at("/redirect", get(redirect))
}

fn main() {}

#[cfg(test)]
mod tests {
    use super::*;
    fn t() {
        let _ = Route::new().at("/should-not-appear", get(index));
    }
}
