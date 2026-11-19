use axum::{
    routing::{get, post, trace, MethodRouter},
    Router,
};

async fn h() -> &'static str { "ok" }

fn login_routes() -> MethodRouter {
    post(h)
}

fn logout_routes() -> MethodRouter {
    return get(h).delete(h);
}

fn app() -> Router {
    let submit = post(h);
    let both = get(h).put(h);
    Router::new()
        .route("/trace", trace(h))
        .route("/submit", submit)
        .route("/both", both)
        .route("/login", login_routes())
        .route("/logout", logout_routes())
}
