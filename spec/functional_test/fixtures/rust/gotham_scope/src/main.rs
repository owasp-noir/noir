// Gotham's scoped routing tree: `build_router(|route| { ... })` with
// `route.scope("/api", |route| { ... })` prepending a path segment,
// nested scopes composing, and `route.with_pipeline_chain(chain,
// |route| { ... })` adding middleware without changing the path.
use gotham::router::builder::*;
use gotham::router::Router;
use gotham::state::State;
use hyper::{Body, Response, StatusCode};

fn index(state: State) -> (State, Response<Body>) {
    let res = Response::builder().status(StatusCode::OK).body("home".into()).unwrap();
    (state, res)
}

fn list_users(state: State) -> (State, Response<Body>) {
    let res = Response::builder().status(StatusCode::OK).body("users".into()).unwrap();
    (state, res)
}

fn create_user(state: State) -> (State, Response<Body>) {
    let res = Response::builder().status(StatusCode::CREATED).body("created".into()).unwrap();
    (state, res)
}

fn show_user(state: State) -> (State, Response<Body>) {
    let res = Response::builder().status(StatusCode::OK).body("user".into()).unwrap();
    (state, res)
}

fn profile(state: State) -> (State, Response<Body>) {
    // Header access still resolves through the composed route.
    let auth = state.headers().get("Authorization");
    let res = Response::builder().status(StatusCode::OK).body("me".into()).unwrap();
    (state, res)
}

fn router() -> Router {
    build_router(default_chain, pipeline_set, |route| {
        route.get("/").to(index);

        route.scope("/api", |route| {
            route.get("/users").to(list_users);
            route.post("/users").to(create_user);

            route.scope("/v2", |route| {
                route.get("/users/:id").to(show_user);
            });

            route.with_pipeline_chain(auth_chain, |route| {
                route.get("/profile").to(profile);
            });
        });
    })
}
