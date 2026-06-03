// Salvo router chains assembled inside a `vec![ ... ]` macro, which is
// the idiomatic shape for `impl Routers`. Exercises: vec!-macro route
// recovery, middleware (`.hoop`) between the path and the verb, verb
// chaining (`.get().post()`), brace path params, and a scoped handler
// path that must not drop the route.
use salvo::prelude::*;

#[handler]
async fn list_users(req: &mut Request) -> &'static str {
    let query: QueryParam = req.extract().await.unwrap();
    let users = UserService::all();
    UserPresenter::render(users)
}

#[handler]
async fn create_user(req: &mut Request) -> &'static str {
    let body: JsonBody<serde_json::Value> = req.extract().await.unwrap();
    UserService::create(body);
    "created"
}

#[handler]
async fn get_user(req: &mut Request) -> String {
    let id = req.param::<String>("id").unwrap();
    let token = req.header("X-Token").unwrap_or_default();
    format!("user {}", id)
}

#[handler]
async fn serve_assets() -> &'static str {
    "asset"
}

pub struct AppRouters;

impl Routers for AppRouters {
    fn build(self) -> Vec<Router> {
        vec![
            Router::new()
                .path("api/users")
                .hoop(auth_middleware)
                .get(list_users)
                .post(create_user),
            Router::with_path("api/users/{id}").get(get_user),
            Router::with_path("assets/{**path}").get(handlers::serve_assets),
        ]
    }
}
