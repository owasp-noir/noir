// Only the production route should surface; the cfg(test)-gated tests module
// below registers routes purely to exercise the router and must be excluded.
use gotham::router::builder::*;
use gotham::router::Router;

fn router() -> Router {
    Router::builder().get("/health").to(health)
}

fn health() {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_router_test() {
        let _ = Router::builder()
            .get("/test-only")
            .to(health)
            .post("/internal/submit")
            .to(health);
    }
}
