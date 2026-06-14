// Cross-fn prefix composition: `warp::path("api").and(backend())` mounts a
// sibling filter-returning fn under the `/api` prefix; the mounted fn's own
// routes must inherit it, and the prefix-only stub must NOT surface as a bare
// `/api`. The `frontend()` static mount is a `.or(...)` sibling at root.
use warp::Filter;

async fn socket_handler() {}
async fn text_handler() {}
async fn stats_handler() {}
async fn health_handler() {}

// Composition root — not a leaf endpoint.
pub fn server() -> impl Filter<Extract = (impl warp::Reply,), Error = warp::Rejection> + Clone {
    warp::path("api").and(backend()).or(frontend())
}

// Sub-router: every route here inherits the `/api` mount prefix. The
// `String` segment parses as a bare identifier inside the `path!` macro
// token tree and must still become a `{param}`.
fn backend() -> impl Filter<Extract = (impl warp::Reply,), Error = warp::Rejection> + Clone {
    let socket = warp::path!("socket" / String)
        .and(warp::ws())
        .and_then(socket_handler);
    let text = warp::path!("text" / String)
        .and(warp::get())
        .and_then(text_handler);
    let stats = warp::path!("stats").and(warp::get()).and_then(stats_handler);
    socket.or(text).or(stats)
}

// Static-file mount: carries no path segment, contributes no endpoint.
fn frontend() -> impl Filter<Extract = (impl warp::Reply,), Error = warp::Rejection> + Clone {
    warp::fs::dir("dist")
}

// A normal (un-mounted) leaf whose `.and(with_state())` value-extractor must
// NOT be mistaken for a sub-router mount (it has no path segment).
pub fn health() -> impl Filter<Extract = (impl warp::Reply,), Error = warp::Rejection> + Clone {
    warp::path!("health")
        .and(warp::get())
        .and(with_state())
        .and_then(health_handler)
}

fn with_state() -> impl Filter<Extract = ((),), Error = std::convert::Infallible> + Clone {
    warp::any().map(|| ())
}

fn main() {}
