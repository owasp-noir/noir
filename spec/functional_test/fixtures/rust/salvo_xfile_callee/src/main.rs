// The route chain references handlers by name, but the `#[handler]` fns live
// in a sibling module (`handler.rs`). The per-file index can't see them, so a
// project-wide handler index supplies their params + callees.
use salvo::prelude::*;

mod handler;

fn route() -> Router {
    Router::new()
        .path("/api")
        .push(Router::new().path("/users").post(handler::create_user))
}
