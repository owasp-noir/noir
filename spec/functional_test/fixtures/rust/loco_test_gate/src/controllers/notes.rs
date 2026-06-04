// Loco controller with explicit routes plus a `#[cfg(test)]` route
// builder that must NOT be reported.
use loco_rs::prelude::*;

async fn list() -> Result<Response> {
    format::empty()
}

async fn create() -> Result<Response> {
    format::empty()
}

pub fn routes() -> Routes {
    Routes::new()
        .prefix("/api/notes")
        .add("/", get(list))
        .add("/", post(create))
}

#[cfg(test)]
mod tests {
    use super::*;

    pub fn test_routes() -> Routes {
        Routes::new()
            .prefix("/should-not-appear")
            .add("/x", get(list))
    }
}
